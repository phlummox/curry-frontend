{-# LANGUAGE FlexibleContexts, BangPatterns, PatternGuards #-}

module Curry.ExtendedFlatTyping(dispType, labelVarsWithTypes, uniqueTypeIndices, genEquations) where

import Text.PrettyPrint.HughesPJ

import Control.Monad.State
import Control.Monad.Reader

import Data.Maybe

import Debug.Trace

import qualified  Data.IntMap as IntMap


import Curry.ExtendedFlat
import Curry.ExtendedFlatGoodies

trace' msg x = x -- trace msg x 

dispType :: TypeExpr -> String
dispType = render . prettyType

prettyType :: TypeExpr -> Doc
prettyType (TVar i) = text ('t':show i)
prettyType (FuncType f x) = parens (prettyType f) <+> text "->" <+> prettyType x
prettyType (TCons qn ts) = let  n = let (m,l) = qnOf qn in m ++ '.' : l
                           in text n <+> hsep (map (parens . prettyType) ts)

prettyAllEqns = render . prettyEqns
    where
      prettyEqn ::(TVarIndex, TypeExpr)  -> Doc
      prettyEqn (l, r) = (char 't' <> int l <+> text "->" <+> prettyType r)

      prettyEqns ((m,l), t, eqns)
          = text m <> char '.' <> text l <+> text "::" <+> prettyType t <> char ':'
            $$ (nest 5 (vcat (map prettyEqn eqns)))


postOrderExpr :: Monad m => (Expr -> m Expr) -> Expr -> m Expr
postOrderExpr f = po
    where po e@(Var _) = f e
          po e@(Lit _) = f e
          po (Comb t n es) = do es' <- mapM po es
                                f (Comb t n es')
          po (Free vs e) = do e' <- po e
                              f (Free vs e')
          po (Let bs e) = do bs' <- mapM poBind bs
                             e'  <- po e
                             f (Let bs' e')
          po (Or l r) = liftM2 Or (po l) (po r) >>= f
          po (Case p t e bs) = do e' <- po e
                                  bs' <- mapM poBranch bs
                                  f (Case p t e' bs')
          poBind  (v, rhs) = do rhs' <- po rhs
                                return (v, rhs')
          poBranch (Branch p rhs) = do rhs' <- po rhs
                                       return (Branch p rhs')




postOrderType :: Monad m => (TypeExpr -> m TypeExpr) -> TypeExpr -> m TypeExpr
postOrderType f = po
    where po e@(TVar _) = f e
          po (FuncType t1 t2) = do t1' <- po t1
                                   t2' <- po t2
                                   f (FuncType t1' t2')
          po (TCons qn ts) = do ts' <- mapM po ts
                                f (TCons qn ts')


visitTVars :: Monad m => (TVarIndex -> m TypeExpr) -> TypeExpr -> m TypeExpr
visitTVars f = postOrderType f'
    where f' (TVar i) = f i
          f' t = return t


-- ----------------------------------------------------------------------
-- ----------------------------------------------------------------------

labelVarsWithTypes :: Prog -> Prog
labelVarsWithTypes = updProgFuncs updateFunc
    where 
      updateFunc = map (\func -> let maxtvi = maxFuncTV func + 1 
                                 in trFunc (foo maxtvi) func)
      foo maxtv qn arity visty te r@(External _) = Func qn arity visty te r
      foo maxtv qn arity visty te r@(Rule vs expr) 
          = let expr' = evalState (runReaderT (withVS vs (po expr)) IntMap.empty) maxtv -- FIXME Argumente in Map
            in Func qn arity visty te (Rule vs expr')

      po :: Expr -> ReaderT TypeMap (State Int) Expr
      -- type information from vi is superseded by type information
      -- from the map. This is okay in the current ciontext, but for
      -- general type inference this would result in loss of information.
      -- (Fix by unifying both types in a later version)
      po e@(Var vi)
          = do vt <- asks (IntMap.lookup $ idxOf vi)
               case vt of
                 Just t -> return (Var vi { typeofVar = Just t })
                 Nothing -> liftM Var (poVarIndex vi)
      po e@(Lit _)
          = return e
      po (Comb t n es)
          = do es' <- mapM po es
               n' <- poQName n
               return (Comb t n' es')
      po (Free vs e) 
          = do vs' <- mapM poVarIndex vs
               e' <- po e
               return (Free vs' e')
      po (Let bs e)
          = do let (vs, es) = unzip bs
               vs' <- mapM poVarIndex vs
               withVS vs' (do es' <- mapM po es
                              e'  <- po e
                              return (Let (zip vs' es') e'))
      po (Or l r)
          = liftM2 Or (po l) (po r)
      po (Case p t e bs)
          = do e' <- po e
               bs' <- mapM poBranch bs
               return (Case p t e' bs')
      poBranch (Branch (Pattern qn vs) rhs) 
          = do qn' <- poQName qn
               vs' <- mapM poVarIndex vs
               withVS vs' (do rhs' <- po rhs
                              return (Branch (Pattern qn' vs') rhs'))
      poBranch (Branch (LPattern l) e) 
          = do rhs' <- po e
               return (Branch (LPattern l) e)
      poVarIndex vi
          = do t <- maybe (lift$freshTVar) return . typeofVar $ vi
               return vi{typeofVar = Just t }

      poQName qn
          = do t <- maybe (lift$freshTVar) 
                        return . typeofQName $ qn
               return qn{typeofQName = Just t }

      withVS :: MonadReader TypeMap m => [VarIndex] -> m a -> m a
      withVS vs action = local (\ m -> foldr (\ v -> IntMap.insert (idxOf v) (fromJust $ typeofVar v)) m vs) action

-- ----------------------------------------------------------------------
-- ----------------------------------------------------------------------
uniqueTypeIndices :: Prog -> Prog
uniqueTypeIndices = updProgFuncs (map updateFunc)
    where
      updateFunc func = let firstfree = maxFuncTV func + 1
                        in (updFuncRule (trRule (ruleFoo firstfree) External)) func
      ruleFoo firstfree args expr
          = let expr' = evalState (postOrderExpr relabelTypes expr) firstfree
            in  Rule args expr'

relabelTypes :: Expr ->  State TVarIndex Expr
relabelTypes (Comb ct qname args)
    = do t' <- case typeofQName qname of
                 Just lt -> relabelType lt
                 Nothing -> freshTVar
         return (Comb ct qname {typeofQName = Just t'} args)
relabelTypes (Var v)
    | typeofVar v == Nothing
    = do t <- freshTVar
         return (Var v{typeofVar = Just t})
relabelTypes (Case p t e bs)
    = do bs' <- mapM relabelPatType bs
         return (Case p t e bs')
    where relabelPatType (Branch (Pattern qn vis) e)
              = do t' <- case typeofQName qn of
                           Just lt -> relabelType lt
                           Nothing -> freshTVar
                   return (Branch (Pattern qn {typeofQName = Just t'} vis) e)
          relabelPatType be = return be
relabelTypes t = return t

relabelType :: TypeExpr -> State TVarIndex TypeExpr
relabelType t = evalStateT (visitTVars typeFoo t) IntMap.empty
    where typeFoo i = do m <- get
                         case IntMap.lookup i m of
                           Just v -> return v
                           Nothing -> do v <- lift freshTVar 
                                         modify (IntMap.insert i v)
                                         return v


-- ----------------------------------------------------------------------
-- ----------------------------------------------------------------------                                

type TypeMap =  IntMap.IntMap TypeExpr

type EqnMonad = StateT TypeMap (State TVarIndex)


genEquations  :: Prog -> Prog
genEquations = updProgFuncs updateFunc
    where 
      updateFunc = map (\func -> let maxtvi = maxFuncTV func + 1 
                                 in trFunc (foo maxtvi) func)
      foo maxtv qn arity visty te r@(External _) = Func qn arity visty te r
      foo maxtv qn arity visty te r@(Rule vs expr) 
          = let h = evalState (execStateT (do argTypes <- mapM varIndexType vs
                                              etype <- equations expr
                                              qnt <- qnType qn
                                              qnt =:= foldr FuncType etype argTypes
                                              return()
                                          ) IntMap.empty) maxtv
            in trace' (prettyAllEqns (qnOf qn,te,IntMap.toList h)) Func qn arity visty (specialiseType h te) (specInRule h (Rule vs expr))
          

equations :: Expr -> EqnMonad TypeExpr
equations = trExpr varIndexType litType combEqn letEqn frEqn orEqn casEqn branchEqn
    where
      litType (Intc _ _)   = preludeType "Int"
      litType (Floatc _ _) = preludeType "Float"
      litType (Charc _ _)  = preludeType "Char"
      preludeType s = return (TCons (mkQName ("Prelude", s)) [])

      combEqn :: (CombType -> QName -> [EqnMonad TypeExpr] -> EqnMonad TypeExpr)
      combEqn _ qn args
          = do resultType <- lift$freshTVar
               argTypes <- sequence args
               tqn <- qnType qn
               tqn =:= foldr FuncType resultType argTypes
               return resultType

      letEqn _ e = e

      frEqn _ e = e

      orEqn l r = do l' <- l
                     r' <- r
                     l' =:= r'

      casEqn :: SrcRef -> CaseType -> EqnMonad TypeExpr -> [(Pattern, EqnMonad TypeExpr)] -> EqnMonad TypeExpr
      casEqn _ _ scr [] = scr >> (lift$freshTVar)
      casEqn _ _ scr ps = do scrt <- scr
                             -- unify patterns with scrutinee
                             mapM_ (unifLhs scrt) ps
                             -- unify right hand sides
                             (p:ps') <- sequence $ map snd ps
                             foldM (=:=) p ps'

      unifLhs scrt (LPattern lit, _)
          = litType lit >>= (=:= scrt)
      unifLhs scrt (Pattern qn vs, _)
          = do qnt <- qnType qn
               argTypes <- mapM varIndexType vs
               qnt =:= foldr FuncType scrt argTypes


      branchEqn :: Pattern -> EqnMonad TypeExpr -> (Pattern, EqnMonad TypeExpr)
      branchEqn p e = (p, e)


unify :: TypeExpr -> TypeExpr -> TypeMap -> TypeMap
-- t =:= u = return t

unify (TVar i) t tm
    | Just s <- IntMap.lookup i tm 
    = unify s t tm
unify s (TVar j) tm
    | Just t <- IntMap.lookup j tm
    = unify s t tm
unify s@(TVar i) t@(TVar j) tm
    | i == j    = tm
    | i < j     = IntMap.insert j s tm
    | i > j     = IntMap.insert i t tm
unify (TVar i) t tm
    = IntMap.insert i t tm
unify s (TVar j) tm
    = IntMap.insert j s tm

unify (FuncType f x) (FuncType g y) tm
    = unify x y (unify f g tm)
unify (TCons m as) (TCons n bs) tm
    | m == n  = foldr ($) tm (zipWith unify as bs)
unify s t _
    = error . render $
      text "Types differ: " <+> prettyType s <+> text "/=" <+> prettyType t


(=:=) :: TypeExpr -> TypeExpr -> EqnMonad TypeExpr
a =:= b = modify (unify a b) >> return a


varIndexType :: VarIndex -> EqnMonad TypeExpr
varIndexType = maybe (lift$freshTVar) return . typeofVar


qnType :: QName -> EqnMonad TypeExpr
qnType = maybe (lift$freshTVar) return . typeofQName

      
freshTVar :: MonadState Int m => m TypeExpr
freshTVar = do nextIdx <- get
               modify succ
               return (TVar nextIdx)



---------------------------------------------------------------------

maxFuncTV = trFunc (\qn _ _ te r -> max (maxQNameTV qn) (max (maxTypeTV te) (maxRuleTV r)))
    where 
      maxRuleTV = trRule (\vis e -> maximum (maxExprTV e : map maxVarIndexTV vis)) (const (-1))

      maxExprTV :: Expr -> Int
      maxExprTV = trExpr var lit comb lt fr max cas branch
          where var  = maxVarIndexTV
                lit  = const (-1)
                comb _ qn ms = maximum (maxQNameTV qn : ms)
                lt bs e = maximum (e : map maxBindTV bs)
                fr vs e = maximum (e : map maxVarIndexTV vs)
                cas _ _ e ps = maximum (e : ps)
                branch p e = max e (maxPatternTV p)

      maxQNameTV = maybe (-1) maxTypeTV . typeofQName

      maxVarIndexTV = maybe (-1) maxTypeTV . typeofVar

      maxBindTV (vi, e) = max e (maxVarIndexTV vi)

      maxPatternTV (Pattern qn vis) = maximum (maxQNameTV qn : map maxVarIndexTV vis)
      maxPatternTV (LPattern _) = -1

      maxTypeTV = trTypeExpr id tapp max
          where tapp _ args = maximum (-1:args)

--------------------


specialiseType :: TypeMap -> TypeExpr -> TypeExpr
specialiseType m t = trTypeExpr (foo m) TCons FuncType t
    where foo m i = maybe (TVar i) (specialiseType m) (IntMap.lookup i m)


-- boilerplate
specInRule :: TypeMap -> Rule -> Rule
specInRule tm = updRule (map specInVarIndex) specInExpr id
    where specInExpr
              = trExpr var Lit comb letexp free Or Case alt
          var vi
              = Var (specInVarIndex vi)
          comb ct qn as
              = Comb ct (specInQName qn) as
          letexp bs e
              = Let (map specInBind bs) e
          free vis e
              = Free (map specInVarIndex vis) e
          alt p e
              = Branch (specInPattern p) e

          specInBind (vi, e)
              = (specInVarIndex vi, e)

          specInPattern (Pattern qn vis)
              = Pattern (specInQName qn) (map specInVarIndex vis)
          specInPattern p = p

          specInVarIndex vi
              = vi { typeofVar = fmap (specialiseType tm) (typeofVar vi)}

          specInQName qn
              = qn { typeofQName = fmap (specialiseType tm) (typeofQName qn)}

