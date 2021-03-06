{- |
    Module      :  $Header$
    Description :  Proper Qualification
    Copyright   :  (c) 2001 - 2004 Wolfgang Lux
                       2005        Martin Engelke
                       2011 - 2015 Björn Peemöller
    License     :  BSD-3-clause

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable

    After checking the module and before starting the translation into the
    intermediate language, the compiler properly qualifies all type
    constructors, data constructors and (global) functions
    occurring in a pattern or expression such that their module prefix
    matches the module of their definition.
    This is done also for functions and constructors declared
    in the current module.
    Only functions and variables declared in local declarations groups
    as well as function arguments remain unchanged.
-}
{-# LANGUAGE CPP #-}
module Transformations.Qual (qual) where

#if __GLASGOW_HASKELL__ < 710
import           Control.Applicative        ((<$>), (<*>))
#endif
import qualified Control.Monad.Reader as R (Reader, asks, runReader)
import           Data.Traversable
import           Prelude hiding            (mapM)

import Curry.Base.Ident
import Curry.Syntax

import Base.TopEnv         (origName)

import Env.TypeConstructor (TCEnv   , qualLookupTC)
import Env.Value           (ValueEnv, qualLookupValue)

data QualEnv = QualEnv
  { moduleIdent :: ModuleIdent
  , tyConsEnv   :: TCEnv
  , valueEnv    :: ValueEnv
  }

type Qual a = a -> R.Reader QualEnv a

qual :: ModuleIdent -> TCEnv -> ValueEnv -> Module -> Module
qual m tcEnv tyEnv mdl = R.runReader (qModule mdl) (QualEnv m tcEnv tyEnv)

qModule :: Qual Module
qModule (Module ps m es is ds) = do
  es' <- qExportSpec es
  ds' <- mapM qDecl  ds
  return (Module ps m es' is ds')

qExportSpec :: Qual (Maybe ExportSpec)
qExportSpec Nothing                 = return Nothing
qExportSpec (Just (Exporting p es)) = (Just . Exporting p) <$> mapM qExport es

qExport :: Qual Export
qExport (Export            x) = Export <$> qIdent x
qExport (ExportTypeWith t cs) = flip ExportTypeWith cs <$> qConstr t
qExport (ExportTypeAll     t) = ExportTypeAll <$> qConstr t
qExport m@(ExportModule    _) = return m

qDecl :: Qual Decl
qDecl i@(InfixDecl     _ _ _ _) = return i
qDecl (DataDecl      p n vs cs) = DataDecl p n vs     <$> mapM qConstrDecl cs
qDecl (NewtypeDecl   p n vs nc) = NewtypeDecl p n vs  <$> qNewConstrDecl nc
qDecl (TypeDecl      p n vs ty) = TypeDecl p n vs     <$> qTypeExpr ty
qDecl (TypeSig         p fs ty) = TypeSig p fs        <$> qTypeExpr ty
qDecl (FunctionDecl    p f eqs) = FunctionDecl p f    <$> mapM qEquation eqs
qDecl (ForeignDecl  p c x n ty) = ForeignDecl p c x n <$> qTypeExpr ty
qDecl e@(ExternalDecl      _ _) = return e
qDecl (PatternDecl     p t rhs) = PatternDecl p <$> qPattern t <*> qRhs rhs
qDecl vs@(FreeDecl         _ _) = return vs

qConstrDecl :: Qual ConstrDecl
qConstrDecl (ConstrDecl p vs      n tys) = ConstrDecl p vs n
                                          <$> mapM qTypeExpr tys
qConstrDecl (ConOpDecl  p vs ty1 op ty2) = flip (ConOpDecl p vs) op
                                          <$> qTypeExpr ty1 <*> qTypeExpr ty2
qConstrDecl (RecordDecl p vs       c fs) = RecordDecl p vs c
                                          <$> mapM qFieldDecl fs

qNewConstrDecl :: Qual NewConstrDecl
qNewConstrDecl (NewConstrDecl p vs n ty)
  = NewConstrDecl p vs n <$> qTypeExpr ty
qNewConstrDecl (NewRecordDecl p vs n (f, ty))
  = (\ty' -> NewRecordDecl p vs n (f, ty')) <$> qTypeExpr ty

qFieldDecl :: Qual FieldDecl
qFieldDecl (FieldDecl p fs ty) = FieldDecl p fs <$> qTypeExpr ty

qTypeExpr :: Qual TypeExpr
qTypeExpr (ConstructorType c tys) = ConstructorType <$> qConstr c
                                                    <*> mapM qTypeExpr tys
qTypeExpr v@(VariableType      _) = return v
qTypeExpr (TupleType         tys) = TupleType <$> mapM qTypeExpr tys
qTypeExpr (ListType           ty) = ListType  <$> qTypeExpr ty
qTypeExpr (ArrowType     ty1 ty2) = ArrowType <$> qTypeExpr ty1
                                              <*> qTypeExpr ty2
qTypeExpr (ParenType          ty) = ParenType <$> qTypeExpr ty

qEquation :: Qual Equation
qEquation (Equation p lhs rhs) = Equation p <$> qLhs lhs <*> qRhs rhs

qLhs :: Qual Lhs
qLhs (FunLhs    f ts) = FunLhs f      <$> mapM qPattern ts
qLhs (OpLhs t1 op t2) = flip OpLhs op <$> qPattern t1 <*> qPattern t2
qLhs (ApLhs   lhs ts) = ApLhs         <$> qLhs lhs <*> mapM qPattern ts

qPattern :: Qual Pattern
qPattern l@(LiteralPattern        _) = return l
qPattern n@(NegativePattern     _ _) = return n
qPattern v@(VariablePattern       _) = return v
qPattern (ConstructorPattern   c ts) = ConstructorPattern
                                       <$> qIdent c <*> mapM qPattern ts
qPattern (InfixPattern     t1 op t2) = InfixPattern <$> qPattern t1
                                       <*> qIdent op <*> qPattern t2
qPattern (ParenPattern            t) = ParenPattern   <$> qPattern t
qPattern (RecordPattern        c fs) = RecordPattern  <$> qIdent c
                                       <*> mapM (qField qPattern) fs
qPattern (TuplePattern         p ts) = TuplePattern p <$> mapM qPattern ts
qPattern (ListPattern          p ts) = ListPattern  p <$> mapM qPattern ts
qPattern (AsPattern             v t) = AsPattern    v <$> qPattern t
qPattern (LazyPattern           p t) = LazyPattern  p <$> qPattern t
qPattern (FunctionPattern      f ts) = FunctionPattern <$> qIdent f
                                                       <*> mapM qPattern ts
qPattern (InfixFuncPattern t1 op t2) = InfixFuncPattern <$> qPattern t1
                                       <*> qIdent op <*> qPattern t2

qRhs :: Qual Rhs
qRhs (SimpleRhs p e ds) = SimpleRhs p <$> qExpr e           <*> mapM qDecl ds
qRhs (GuardedRhs es ds) = GuardedRhs  <$> mapM qCondExpr es <*> mapM qDecl ds

qCondExpr :: Qual CondExpr
qCondExpr (CondExpr p g e) = CondExpr p <$> qExpr g <*> qExpr e

qExpr :: Qual Expression
qExpr l@(Literal             _) = return l
qExpr (Variable              v) = Variable       <$> qIdent v
qExpr (Constructor           c) = Constructor    <$> qIdent c
qExpr (Paren                 e) = Paren          <$> qExpr e
qExpr (Typed              e ty) = Typed          <$> qExpr e <*> qTypeExpr ty
qExpr (Record             c fs) = Record <$> qIdent c <*> mapM (qField qExpr) fs
qExpr (RecordUpdate       e fs) = RecordUpdate   <$> qExpr e
                                                 <*> mapM (qField qExpr) fs
qExpr (Tuple              p es) = Tuple p        <$> mapM qExpr es
qExpr (List               p es) = List p         <$> mapM qExpr es
qExpr (ListCompr        p e qs) = ListCompr p    <$> qExpr e <*> mapM qStmt qs
qExpr (EnumFrom              e) = EnumFrom       <$> qExpr e
qExpr (EnumFromThen      e1 e2) = EnumFromThen   <$> qExpr e1 <*> qExpr e2
qExpr (EnumFromTo        e1 e2) = EnumFromTo     <$> qExpr e1 <*> qExpr e2
qExpr (EnumFromThenTo e1 e2 e3) = EnumFromThenTo <$> qExpr e1 <*> qExpr e2
                                                              <*> qExpr e3
qExpr (UnaryMinus         op e) = UnaryMinus op  <$> qExpr e
qExpr (Apply             e1 e2) = Apply          <$> qExpr e1 <*> qExpr e2
qExpr (InfixApply     e1 op e2) = InfixApply     <$> qExpr e1 <*> qInfixOp op
                                                              <*> qExpr e2
qExpr (LeftSection        e op) = LeftSection  <$> qExpr e <*> qInfixOp op
qExpr (RightSection       op e) = RightSection <$> qInfixOp op <*> qExpr e
qExpr (Lambda           r ts e) = Lambda r     <$> mapM qPattern ts <*> qExpr e
qExpr (Let                ds e) = Let <$> mapM qDecl ds  <*> qExpr e
qExpr (Do                sts e) = Do <$>  mapM qStmt sts <*> qExpr e
qExpr (IfThenElse   r e1 e2 e3) = IfThenElse r <$> qExpr e1 <*> qExpr e2
                                                            <*> qExpr e3
qExpr (Case          r ct e as) = Case r ct    <$> qExpr e <*> mapM qAlt as

qStmt :: Qual Statement
qStmt (StmtExpr p   e) = StmtExpr p <$> qExpr e
qStmt (StmtBind p t e) = StmtBind p <$> qPattern t <*> qExpr e
qStmt (StmtDecl    ds) = StmtDecl   <$> mapM qDecl ds

qAlt :: Qual Alt
qAlt (Alt p t rhs) = Alt p <$> qPattern t <*> qRhs rhs

qField :: Qual a -> Qual (Field a)
qField q (Field p l x) = Field p <$> qIdent l <*> q x

qInfixOp :: Qual InfixOp
qInfixOp (InfixOp     op) = InfixOp     <$> qIdent op
qInfixOp (InfixConstr op) = InfixConstr <$> qIdent op

qIdent :: Qual QualIdent
qIdent x | isQualified x                = x'
         | hasGlobalScope (unqualify x) = x'
         | otherwise                    = return x
  where
  x' = do
    m     <- R.asks moduleIdent
    tyEnv <- R.asks valueEnv
    return $ case qualLookupValue x tyEnv of
      [y] -> origName y
      _   -> case qualLookupValue qmx tyEnv of
        [y] -> origName y
        _   -> qmx
        where qmx = qualQualify m x

qConstr :: Qual QualIdent
qConstr x = do
  m     <- R.asks moduleIdent
  tcEnv <- R.asks tyConsEnv
  return $ case qualLookupTC x tcEnv of
    [y] -> origName y
    _   -> case qualLookupTC qmx tcEnv of
      [y] -> origName y
      _   -> qmx
      where qmx = qualQualify m x
