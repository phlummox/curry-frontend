{- |
    Module      :  $Header$
    Description :  Checks consistency of interface files
    Copyright   :  (c) 2000 - 2007 Wolfgang Lux
                       2015        Jan Tikovsky
    License     :  BSD-3-clause

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable

   Interface files include declarations of all entities that are exported
   by the module, but defined in another module. Since these declarations
   can become inconsistent if client modules are not recompiled properly,
   the compiler checks that all imported declarations in an interface
   agree with their original definitions.

   One may ask why we include imported declarations at all, if the
   compiler always has to compare those declarations with the original
   definitions. The main reason for this is that it helps to avoid
   unnecessary recompilations of client modules. As an example, consider
   the three modules:

     module A where { data T = C }
     module B(T(..)) where { import A }
     module C where { import B; f = C }

   where module B could be considered as a public interface of module A,
   which restricts access to type A.T and its constructor C.
   The client module C imports this type via the public interface B.
   If now module A is changed by adding a definition of a new global function

     module A where { data T = C; f = C }

   module B must be recompiled because A's interface is changed.
   On the other hand, module C need not be recompiled because the change in
   A does not affect B's interface. By including the declaration of type A.T
   in B's interface, the compiler can trivially check that B's interface
   remains unchanged and therefore the client module C is not recompiled.

   Another reason for including imported declarations in interfaces is
   that the compiler in principle could avoid loading interfaces of
   modules that are imported only indirectly, which would save processing
   time and allow distributing binary packages of a library with a public
   interface module only. However, this has not been implemented yet.
-}

module Checks.InterfaceCheck (interfaceCheck) where

import           Control.Monad            (unless)
import qualified Control.Monad.State as S
import           Data.Maybe               (fromMaybe)

import Curry.Base.Ident
import Curry.Base.Position
import Curry.Base.Pretty
import Curry.Syntax

import Base.CurryTypes
import Base.Messages (Message, posMessage, internalError)
import Base.TopEnv
import Base.Types
import Env.OpPrec
import Env.TypeConstructor
import Env.Value

data ICState = ICState
  { moduleIdent :: ModuleIdent
  , precEnv     :: OpPrecEnv
  , tyConsEnv   :: TCEnv
  , valueEnv    :: ValueEnv
  , errors      :: [Message]
  }

type IC = S.State ICState

getModuleIdent :: IC ModuleIdent
getModuleIdent = S.gets moduleIdent

getPrecEnv :: IC OpPrecEnv
getPrecEnv = S.gets precEnv

getTCEnv :: IC TCEnv
getTCEnv = S.gets tyConsEnv

getValueEnv :: IC ValueEnv
getValueEnv = S.gets valueEnv

-- |Report a syntax error
report :: Message -> IC ()
report msg = S.modify $ \ s -> s { errors = msg : errors s }

ok :: IC ()
ok = return ()

interfaceCheck :: OpPrecEnv -> TCEnv -> ValueEnv -> Interface -> [Message]
interfaceCheck pEnv tcEnv tyEnv (Interface m _ ds) = reverse (errors s)
  where s = S.execState (mapM_ checkImport ds) (ICState m pEnv tcEnv tyEnv [])

checkImport :: IDecl -> IC ()
checkImport (IInfixDecl p fix pr op) = checkPrecInfo check p op
  where check (PrecInfo op' (OpPrec fix' pr')) =
          op == op' && fix == fix' && pr == pr'
checkImport (HidingDataDecl p tc tvs)
  = checkTypeInfo "hidden data type" check p tc
  where check (DataType     tc' n' _)
          | tc == tc' && length tvs == n' = Just ok
        check (RenamingType tc' n' _)
          | tc == tc' && length tvs == n' = Just ok
        check _                           = Nothing
checkImport (IDataDecl p tc tvs cs _) = checkTypeInfo "data type" check p tc
  where check (DataType     tc' n' cs')
          | tc == tc' && length tvs == n' &&
            (null cs || map constrId cs == map constrIdent cs')
          = Just (mapM_ (checkConstrImport tc tvs) cs)
        check (RenamingType tc' n'   _)
          | tc == tc' && length tvs == n' && null cs = Just ok
        check _ = Nothing
checkImport (INewtypeDecl p tc tvs nc _)
  = checkTypeInfo "newtype" check p tc
  where check (RenamingType tc' n' nc')
          | tc == tc' && length tvs == n' && nconstrId nc == constrIdent nc'
          = Just (checkNewConstrImport tc tvs nc)
        check _ = Nothing
checkImport (ITypeDecl p tc tvs ty) = do
  m <- getModuleIdent
  let check (AliasType tc' n' ty')
        | tc == tc' && length tvs == n' && toQualType m tvs ty == ty'
        = Just ok
      check _ = Nothing
  checkTypeInfo "synonym type" check p tc
checkImport (IFunctionDecl p f n ty) = do
  m <- getModuleIdent
  let check (Value f' n' (ForAll _ ty')) =
        f == f' && n' == n && toQualType m [] ty == ty'
      check _ = False
  checkValueInfo "function" check p f

checkConstrImport :: QualIdent -> [Ident] -> ConstrDecl -> IC ()
checkConstrImport tc tvs (ConstrDecl p evs c tys) = do
  m <- getModuleIdent
  let qc = qualifyLike tc c
      checkConstr (DataConstructor c' _ _ (ForAllExist uqvs eqvs ty')) =
        qc == c' && length evs == eqvs && length tvs == uqvs &&
        toQualTypes m tvs tys == arrowArgs ty'
      checkConstr _ = False
  checkValueInfo "data constructor" checkConstr p qc
checkConstrImport tc tvs (ConOpDecl p evs ty1 op ty2) = do
  m <- getModuleIdent
  let qc = qualifyLike tc op
      checkConstr (DataConstructor c' _ _ (ForAllExist uqvs eqvs ty')) =
        qc == c' && length evs == eqvs && length tvs == uqvs &&
        toQualTypes m tvs [ty1,ty2] == arrowArgs ty'
      checkConstr _ = False
  checkValueInfo "data constructor" checkConstr p qc
checkConstrImport tc tvs (RecordDecl p evs c fs) = do
  m <- getModuleIdent
  let qc = qualifyLike tc c
      (ls, tys) = unzip [(l, ty) | FieldDecl _ labels ty <- fs, l <- labels]
      checkConstr (DataConstructor c' _ ls' (ForAllExist uqvs eqvs ty')) =
        qc == c' && length evs == eqvs && length tvs == uqvs && ls == ls' &&
        toQualTypes m tvs tys == arrowArgs ty'
      checkConstr _ = False
  checkValueInfo "data constructor" checkConstr p qc

checkNewConstrImport :: QualIdent -> [Ident] -> NewConstrDecl -> IC ()
checkNewConstrImport tc tvs (NewConstrDecl p evs c ty) = do
  m <- getModuleIdent
  let qc = qualifyLike tc c
      checkNewConstr (NewtypeConstructor c' _ (ForAllExist uqvs eqvs ty')) =
        qc == c' && length evs == eqvs && length tvs == uqvs &&
        toQualType m tvs ty == head (arrowArgs ty')
      checkNewConstr _ = False
  checkValueInfo "newtype constructor" checkNewConstr p qc
checkNewConstrImport tc tvs (NewRecordDecl p evs c (l, ty)) = do
  m <- getModuleIdent
  let qc = qualifyLike tc c
      checkNewConstr (NewtypeConstructor c' l' (ForAllExist uqvs eqvs ty')) =
        qc == c' && length evs == eqvs && length tvs == uqvs && l == l' &&
        toQualType m tvs ty == head (arrowArgs ty')
      checkNewConstr _ = False
  checkValueInfo "newtype constructor" checkNewConstr p qc

checkPrecInfo :: (PrecInfo -> Bool) -> Position -> QualIdent -> IC ()
checkPrecInfo check p op = do
  pEnv <- getPrecEnv
  let checkInfo m op' = case qualLookupTopEnv op pEnv of
        []     -> report $ errNoPrecedence p m op'
        [prec] -> unless (check prec)
                         (report $ errImportConflict p "precedence" m op')
        _      -> internalError "checkPrecInfo"
  checkImported checkInfo op

checkTypeInfo :: String -> (TypeInfo -> Maybe (IC ())) -> Position
              -> QualIdent -> IC ()
checkTypeInfo what check p tc = do
  tcEnv <- getTCEnv
  let checkInfo m tc' = case qualLookupTopEnv tc tcEnv of
        []   -> report $ errNotExported p what m tc'
        [ti] -> fromMaybe (report $ errImportConflict p what m tc') (check ti)
        _    -> internalError "checkTypeInfo"
  checkImported checkInfo tc

checkValueInfo :: String -> (ValueInfo -> Bool) -> Position
               -> QualIdent -> IC ()
checkValueInfo what check p x = do
  tyEnv <- getValueEnv
  let checkInfo m x' = case qualLookupTopEnv x tyEnv of
        []   -> report $ errNotExported p what m x'
        [vi] -> unless (check vi) (report $ errImportConflict p what m x')
        _    -> internalError "checkValueInfo"
  checkImported checkInfo x

checkImported :: (ModuleIdent -> Ident -> IC ()) -> QualIdent -> IC ()
checkImported _ (QualIdent Nothing  _) = ok
checkImported f (QualIdent (Just m) x) = f m x

-- ---------------------------------------------------------------------------
-- Error messages
-- ---------------------------------------------------------------------------

errNotExported :: Position -> String -> ModuleIdent -> Ident -> Message
errNotExported p what m x = posMessage p $
  text "Inconsistent module interfaces"
  $+$ text "Module" <+> text (moduleName m)
  <+> text "does not export"<+> text what <+> text (escName x)

errNoPrecedence :: Position -> ModuleIdent -> Ident -> Message
errNoPrecedence p m x = posMessage p $
  text "Inconsistent module interfaces"
  $+$ text "Module" <+> text (moduleName m)
  <+> text "does not define a precedence for" <+> text (escName x)

errImportConflict :: Position -> String -> ModuleIdent -> Ident -> Message
errImportConflict p what m x = posMessage p $
  text "Inconsistent module interfaces"
  $+$ text "Declaration of" <+> text what <+> text (escName x)
  <+> text "does not match its definition in module" <+> text (moduleName m)
