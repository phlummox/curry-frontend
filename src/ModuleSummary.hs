{- |ModuleSummary - Generates a record containing extracted and prepared data
              from a 'Curry.Syntax.Module'

    November 2005, Martin Engelke (men@informatik.uni-kiel.de)
-}
module ModuleSummary (ModuleSummary (..), summarizeModule) where

import Data.Maybe

import Curry.Base.Position
import Curry.Base.Ident
import Curry.Syntax

import Base.Messages (internalError)
import Base.Types

import Env.TypeConstructors (TCEnv, TypeInfo (..), qualLookupTC)

-- |A record containing data for a module 'm'
data ModuleSummary = ModuleSummary
  { moduleId     :: ModuleIdent -- ^The name of 'm'
  , interface    :: [IDecl]     -- ^all exported declarations in 'm'
                                --  (including exported imports)
  , exports      :: [Export]    -- ^The export list extracted from 'm'
  , imports      :: [IDecl]     -- ^imports
  , infixDecls   :: [IDecl]     -- ^Interfaces of all infix declarations in 'm'
  , typeSynonyms :: [IDecl]     -- ^Interfaces of all type synonyms in 'm'
  } deriving Show


{- |Return a 'ModuleSummary' for a module, its corresponding
    table of type constructors and its interface
-}
summarizeModule :: TCEnv -> Interface -> Module -> ModuleSummary
summarizeModule tcEnv (Interface iid idecls) mdl@(Module mid mExp decls)
  | iid == mid = ModuleSummary
      { moduleId     = mid
      , interface    = idecls
      , exports      = maybe [] (\ (Exporting _ exps) -> exps) mExp
      , imports      = genImports decls
      , infixDecls   = genInfixDecls mdl
      , typeSynonyms = genTypeSyns tcEnv mdl
      }
  | otherwise
    = internalError $  "ModuleSummary: interface \"" ++ show iid
                    ++ "\" does not match module \"" ++ show mid ++ "\""

-- ---------------------------------------------------------------------------

-- |Generate interface import declarations
genImports :: [Decl] -> [IDecl]
genImports = map snd . foldr addImport []
  where
  addImport :: Decl -> [(ModuleIdent, IDecl)] -> [(ModuleIdent, IDecl)]
  addImport (ImportDecl pos mid _ _ _) imps = case lookup mid imps of
    Nothing -> (mid, IImportDecl pos mid) : imps
    Just _  -> imps
  addImport _ imps = imps

-- ---------------------------------------------------------------------------

-- |Generate interface infix declarations in the module
genInfixDecls :: Module -> [IDecl]
genInfixDecls (Module mident _ decls) = mapMaybe genInfixDecl decls
  where
  genInfixDecl :: Decl -> Maybe IDecl
  genInfixDecl (InfixDecl pos spec prec idents)
    = Just $ map (IInfixDecl pos spec prec . qualifyWith mident) idents
  genInfixDecl _ = Nothing

--   collectIInfixDecls mident decls
--   collectIInfixDecls :: ModuleIdent -> [Decl] -> [IDecl]
--   collectIInfixDecls _ [] = []
--   collectIInfixDecls mident ((InfixDecl pos infixspec prec idents) : decls)
--     =  map (IInfixDecl pos infixspec prec . qualifyWith mident) idents
--     ++ collectIInfixDecls mident decls
--   collectIInfixDecls mident (_ : decls) = collectIInfixDecls mident decls

-- ---------------------------------------------------------------------------

-- |Generate interface declarations for all type synonyms in the module.
genTypeSyns :: TCEnv -> Module -> [IDecl]
genTypeSyns tcEnv (Module mident _ decls)
  = concatMap (genTypeSynDecl mident tcEnv) $ filter isTypeSyn decls

isTypeSyn :: Decl -> Bool
isTypeSyn (TypeDecl _ _ _ texpr) = case texpr of
  RecordType _ _ -> False
  _              -> True
isTypeSyn _ = False

--
genTypeSynDecl :: ModuleIdent -> TCEnv -> Decl -> [IDecl]
genTypeSynDecl mid tcEnv (TypeDecl pos ident params texpr)
  = [genTypeDecl pos mid ident params tcEnv texpr]
genTypeSynDecl _ _ _
  = []

--
genTypeDecl :: Position -> ModuleIdent -> Ident -> [Ident] -> TCEnv
	    -> TypeExpr -> IDecl
genTypeDecl pos mid ident params tcEnv texpr
  = ITypeDecl pos (qualifyWith mid ident) params (modifyTypeExpr tcEnv texpr)

--
modifyTypeExpr :: TCEnv -> TypeExpr -> TypeExpr
modifyTypeExpr tcEnv (ConstructorType qident typeexprs)
  = case qualLookupTC qident tcEnv of
      [AliasType _ arity rhstype]
        -> modifyTypeExpr tcEnv
              (genTypeSynDeref (zip [0 .. arity - 1] typeexprs) rhstype)
      _ -> ConstructorType (fromMaybe qident (lookupTCId qident tcEnv))
                           (map (modifyTypeExpr tcEnv) typeexprs)
modifyTypeExpr _ (VariableType ident)
  = VariableType ident
modifyTypeExpr tcEnv (ArrowType type1 type2)
  = ArrowType (modifyTypeExpr tcEnv type1) (modifyTypeExpr tcEnv type2)
modifyTypeExpr tcEnv (TupleType typeexprs)
  | null typeexprs
    = ConstructorType qUnitId []
  | otherwise
    = ConstructorType (qTupleId (length typeexprs))
                      (map (modifyTypeExpr tcEnv) typeexprs)
modifyTypeExpr tcEnv (ListType typeexpr)
  = ConstructorType (qualify listId) [(modifyTypeExpr tcEnv typeexpr)]
modifyTypeExpr tcEnv (RecordType fields rtype)
  = RecordType
    (map (\ (labs, texpr) -> (labs, (modifyTypeExpr tcEnv texpr))) fields)
    (maybe Nothing (Just . modifyTypeExpr tcEnv) rtype)

--
genTypeSynDeref :: [(Int, TypeExpr)] -> Type -> TypeExpr
genTypeSynDeref its (TypeVariable i) = case lookup i its of
  Nothing -> internalError "@CurryInfo.genTypeSynDeref: unkown type var index"
  Just te -> te
genTypeSynDeref its (TypeConstructor qid tyexps)
  = ConstructorType qid $ map (genTypeSynDeref its) tyexps
genTypeSynDeref its (TypeArrow type1 type2)
  = ArrowType (genTypeSynDeref its type1) (genTypeSynDeref its type2)
genTypeSynDeref its (TypeRecord fields ri)
  = RecordType
    (map (\ (lab, texpr) -> ([lab], genTypeSynDeref its texpr)) fields)
    (fmap (Just . genTypeSynDeref its . TypeVariable) ri)
genTypeSynDeref _ (TypeConstrained _ _) = internalError
  "@CurryInfo.genTypeSynDeref: illegal constrained type occured"
genTypeSynDeref _ (TypeSkolem _) = internalError
  "@CurryInfo.genTypeSynDeref: illegal skolem type occured"


--
lookupTCId :: QualIdent -> TCEnv -> Maybe QualIdent
lookupTCId qident tcEnv = case qualLookupTC qident tcEnv of
  [DataType     qid _ _] -> Just qid
  [RenamingType qid _ _] -> Just qid
  [AliasType    qid _ _] -> Just qid
  _                      -> Nothing
