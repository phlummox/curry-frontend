{- |
    Module      :  $Header$
    Description :  Checks interface declarations
    Copyright   :  (c) 2000 - 2007 Wolfgang Lux
                       2011 - 2015 Björn Peemöller
                       2015        Jan Tikovsky
    License     :  BSD-3-clause

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable

   Similar to Curry source files, some post-processing has to be applied
   to parsed interface files. In particular, the compiler must
   disambiguate nullary type constructors and type variables. In
   addition, the compiler also checks that all type constructor
   applications are saturated. Since interface files are closed -- i.e.,
   they include declarations of all entities which are defined in other
   modules -- the compiler can perform this check without reference to
   the global environments.
-}

module Checks.InterfaceSyntaxCheck (intfSyntaxCheck) where

import           Control.Monad            (liftM, liftM2)
import qualified Control.Monad.State as S
import           Data.List                (nub, partition)

import Base.Expr
import Base.Messages (Message, posMessage, internalError)
import Base.TopEnv
import Base.Utils    (findMultiples)
import Env.TypeConstructor

import Curry.Base.Ident
import Curry.Base.Pretty
import Curry.Syntax

data ISCState = ISCState
  { typeEnv :: TypeEnv
  , errors  :: [Message]
  }

type ISC = S.State ISCState

getTypeEnv :: ISC TypeEnv
getTypeEnv = S.gets typeEnv

-- |Report a syntax error
report :: Message -> ISC ()
report msg = S.modify $ \ s -> s { errors = msg : errors s }

intfSyntaxCheck :: Interface -> (Interface, [Message])
intfSyntaxCheck (Interface n is ds) = (Interface n is ds', reverse $ errors s')
  where (ds', s') = S.runState (mapM checkIDecl ds) (ISCState env [])
        env = foldr bindType (fmap typeKind initTCEnv) ds

-- The compiler requires information about the arity of each defined type
-- constructor as well as information whether the type constructor
-- denotes an algebraic data type, a renaming type, or a type synonym.
-- The latter must not occur in type expressions in interfaces.

bindType :: IDecl -> TypeEnv -> TypeEnv
bindType (IInfixDecl         _ _ _ _) = id
bindType (HidingDataDecl      _ tc _) = qualBindTopEnv tc (Data tc [])
bindType (IDataDecl      _ tc _ cs _) = qualBindTopEnv tc
                                      (Data tc (map constrId cs))
bindType (INewtypeDecl   _ tc _ nc _) = qualBindTopEnv tc (Data tc [nconstrId nc])
bindType (ITypeDecl         _ tc _ _) = qualBindTopEnv tc (Alias tc)
bindType (IFunctionDecl      _ _ _ _) = id

-- The checks applied to the interface are similar to those performed
-- during syntax checking of type expressions.

checkIDecl :: IDecl -> ISC IDecl
checkIDecl (IInfixDecl  p fix pr op) = return (IInfixDecl p fix pr op)
checkIDecl (HidingDataDecl p tc tvs) = do
  checkTypeLhs tvs
  return (HidingDataDecl p tc tvs)
checkIDecl (IDataDecl p tc tvs cs hs) = do
  checkTypeLhs tvs
  checkHidden tc (cons ++ labels) hs
  cs' <- mapM (checkConstrDecl tvs) cs
  return $ IDataDecl p tc tvs cs' hs
  where cons   = map constrId cs
        labels = nub $ concatMap recordLabels cs
checkIDecl (INewtypeDecl p tc tvs nc hs) = do
  checkTypeLhs tvs
  checkHidden tc (con : labels) hs
  nc' <- checkNewConstrDecl tvs nc
  return $ INewtypeDecl p tc tvs nc' hs
  where con    = nconstrId nc
        labels = nrecordLabels nc
checkIDecl (ITypeDecl p tc tvs ty) = do
  checkTypeLhs tvs
  liftM (ITypeDecl p tc tvs) (checkClosedType tvs ty)
checkIDecl (IFunctionDecl p f n ty) =
  liftM (IFunctionDecl p f n) (checkType ty)

checkHidden :: QualIdent -> [Ident] -> [Ident] -> ISC ()
checkHidden tc csls hs =
  mapM_ (report . errNoElement tc) $ nub $ filter (`notElem` csls) hs

checkTypeLhs :: [Ident] -> ISC ()
checkTypeLhs tvs = do
  tyEnv <- getTypeEnv
  let (tcs, tvs') = partition isTypeConstr tvs
      isTypeConstr tv = not (null (lookupTopEnv tv tyEnv))
  mapM_ (report . errNoVariable)       (nub tcs)
  mapM_ (report . errNonLinear . head) (findMultiples tvs')

checkConstrDecl :: [Ident] -> ConstrDecl -> ISC ConstrDecl
checkConstrDecl tvs (ConstrDecl p evs c tys) = do
  checkTypeLhs evs
  liftM (ConstrDecl p evs c) (mapM (checkClosedType tvs') tys)
  where tvs' = evs ++ tvs
checkConstrDecl tvs (ConOpDecl p evs ty1 op ty2) = do
  checkTypeLhs evs
  liftM2 (\t1 t2 -> ConOpDecl p evs t1 op t2)
         (checkClosedType tvs' ty1)
         (checkClosedType tvs' ty2)
  where tvs' = evs ++ tvs
checkConstrDecl tvs (RecordDecl p evs c fs) = do
  checkTypeLhs evs
  liftM (RecordDecl p evs c) (mapM (checkFieldDecl tvs') fs)
  where tvs' = evs ++ tvs

checkFieldDecl :: [Ident] -> FieldDecl -> ISC FieldDecl
checkFieldDecl tvs (FieldDecl p ls ty) =
  liftM (FieldDecl p ls) (checkClosedType tvs ty)

checkNewConstrDecl :: [Ident] -> NewConstrDecl -> ISC NewConstrDecl
checkNewConstrDecl tvs (NewConstrDecl p evs c ty) = do
  checkTypeLhs evs
  liftM (NewConstrDecl p evs c) (checkClosedType tvs' ty)
  where tvs' = evs ++ tvs
checkNewConstrDecl tvs (NewRecordDecl p evs c (l,ty)) = do
  checkTypeLhs evs
  ty' <- checkClosedType tvs' ty
  return $ NewRecordDecl p evs c (l,ty')
  where tvs' = evs ++ tvs

checkClosedType :: [Ident] -> TypeExpr -> ISC TypeExpr
checkClosedType tvs ty = do
  ty' <- checkType ty
  mapM_ (report . errUnboundVariable) (nub (filter (`notElem` tvs) (fv ty')))
  return ty'

checkType :: TypeExpr -> ISC TypeExpr
checkType (ConstructorType tc tys) = checkTypeConstructor tc tys
checkType (VariableType        tv) = checkType (ConstructorType (qualify tv) [])
checkType (TupleType          tys) = liftM TupleType (mapM checkType tys)
checkType (ListType            ty) = liftM ListType (checkType ty)
checkType (ArrowType      ty1 ty2) = liftM2 ArrowType (checkType ty1) (checkType ty2)
checkType (ParenType           ty) = liftM ParenType (checkType ty)

checkTypeConstructor :: QualIdent -> [TypeExpr] -> ISC TypeExpr
checkTypeConstructor tc tys = do
  tyEnv <- getTypeEnv
  case qualLookupTopEnv tc tyEnv of
    [] | not (isQualified tc) && null tys -> return (VariableType (unqualify tc))
       | otherwise                        -> do
          report (errUndefinedType tc)
          ConstructorType tc `liftM` mapM checkType tys
    [Data _ _] -> ConstructorType tc `liftM` mapM checkType tys
    [Alias  _] -> do
                  report (errBadTypeSynonym tc)
                  ConstructorType tc `liftM` mapM checkType tys
    _          -> internalError "checkTypeConstructor"

-- ---------------------------------------------------------------------------
-- Error messages
-- ---------------------------------------------------------------------------

errUndefinedType :: QualIdent -> Message
errUndefinedType tc = posMessage tc
                    $ text "Undefined type" <+> text (qualName tc)

errNonLinear :: Ident -> Message
errNonLinear tv = posMessage tv $ hsep $ map text
  [ "Type variable", escName tv
  , "occurs more than once on left hand side of type declaration"
  ]

errNoVariable :: Ident -> Message
errNoVariable tv = posMessage tv $ hsep $ map text
  [ "Type constructor", escName tv
  , "used in left hand side of type declaration"
  ]

errUnboundVariable :: Ident -> Message
errUnboundVariable tv = posMessage tv $
  text "Undefined type variable" <+> text (escName tv)

errBadTypeSynonym :: QualIdent -> Message
errBadTypeSynonym tc = posMessage tc $ text "Synonym type"
                    <+> text (qualName tc) <+> text "in interface"

errNoElement :: QualIdent -> Ident -> Message
errNoElement tc x = posMessage tc $ hsep $ map text
  [ "Hidden constructor or label ", escName x
  , " is not defined for type ", qualName tc
  ]
