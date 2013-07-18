{- |
    Module      :  $Header$
    Description :  Different checks on a Curry module
    Copyright   :  (c) 2011, Björn Peemöller (bjp@informatik.uni-kiel.de)
    License     :  OtherLicense

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable

    This module subsumes the different checks to be performed on a Curry
    module during compilation, e.g. type checking.
-}
module Checks where

import Curry.Syntax (Module (..), Interface (..))

import Base.Messages

import qualified Checks.InterfaceCheck   as IC (interfaceCheck)
import qualified Checks.ExportCheck      as EC (exportCheck)
import qualified Checks.KindCheck        as KC (kindCheck)
import qualified Checks.PrecCheck        as PC (precCheck)
import qualified Checks.SyntaxCheck      as SC (syntaxCheck)
import qualified Checks.TypeCheck        as TC (typeCheck)
import qualified Checks.WarnCheck        as WC (warnCheck)
import qualified Checks.TypeClassesCheck as TCC (typeClassesCheck)

import CompilerEnv
import CompilerOpts

data CheckResult a
  = CheckSuccess a
  | CheckFailed [Message]

instance Monad CheckResult where
  return = CheckSuccess
  (>>=)  = thenCheck

thenCheck :: CheckResult a -> (a -> CheckResult b) -> CheckResult b
thenCheck chk cont = case chk of
  CheckSuccess   a -> cont a
  CheckFailed errs -> CheckFailed errs

-- TODO: More documentation

interfaceCheck :: CompilerEnv -> Interface -> CheckResult ()
interfaceCheck env intf
  | null errs = return ()
  | otherwise = CheckFailed errs
  where errs = IC.interfaceCheck (opPrecEnv env) (tyConsEnv env)
                                 (valueEnv env) intf

-- |Check the kinds of type definitions and signatures.
--
-- * Declarations: Nullary type constructors and type variables are
--                 disambiguated
-- * Environment:  remains unchanged
kindCheck :: CompilerEnv -> Module -> CheckResult (CompilerEnv, Module)
kindCheck env (Module m es is ds)
  | null msgs = CheckSuccess (env, Module m es is ds')
  | otherwise = CheckFailed msgs
  where (ds', msgs) = KC.kindCheck (moduleIdent env) (tyConsEnv env) ds

-- |Check for a correct syntax.
--
-- * Declarations: Nullary data constructors and variables are
--                 disambiguated, variables are renamed
-- * Environment:  remains unchanged
syntaxCheck :: Options -> CompilerEnv -> Module -> CheckResult (CompilerEnv, Module)
syntaxCheck opts env (Module m es is ds)
  | null msgs = CheckSuccess (env, Module m es is ds')
  | otherwise = CheckFailed msgs
  where (ds', msgs) = SC.syntaxCheck opts (moduleIdent env)
                      (valueEnv env) (tyConsEnv env) ds

-- |Check the precedences of infix operators.
--
-- * Declarations: Expressions are reordered according to the specified
--                 precedences
-- * Environment:  The operator precedence environment is updated
precCheck :: CompilerEnv -> Module -> CheckResult (CompilerEnv, Module)
precCheck env (Module m es is ds)
  | null msgs = CheckSuccess (env { opPrecEnv = pEnv' }, Module m es is ds')
  | otherwise = CheckFailed msgs
  where (ds', pEnv', msgs) = PC.precCheck (moduleIdent env) (opPrecEnv env) ds

-- |Apply the correct typing of the module.
-- Parts of the syntax tree are annotated by their type; the type constructor
-- and value environments are updated.
typeCheck :: Bool -> CompilerEnv -> Module -> CheckResult (CompilerEnv, Module)
typeCheck run env (Module m es is ds)
  | null msgs = CheckSuccess (env { tyConsEnv = tcEnv', valueEnv = tyEnv' }, 
                  (Module m es is newDecls))
  | otherwise = CheckFailed msgs
  where 
  (tcEnv', tyEnv', newDecls, msgs) 
    = TC.typeCheck (moduleIdent env) (tyConsEnv env) (valueEnv env) 
                   (classEnv env) True run ds
                   

-- |Check the export specification
exportCheck :: Bool -> CompilerEnv -> Module -> CheckResult (CompilerEnv, Module)
exportCheck tcs env (Module m es is ds)
  | null msgs = CheckSuccess (env, Module m es' is ds)
  | otherwise = CheckFailed msgs
  where (es', msgs) = EC.exportCheck tcs (moduleIdent env) (aliasEnv env)
                                     (tyConsEnv env) (valueEnv env) 
                                     (classEnv env) es

-- TODO: Which kind of warnings?

-- |Check for warnings.
warnCheck :: CompilerEnv -> Module -> [Message]
warnCheck env mdl = WC.warnCheck (valueEnv env) mdl

-- |Check the type classes
-- Changes the classes environment and removes class and instance declarations, 
-- furthermore adds new code for them
typeClassesCheck :: CompilerEnv -> Module -> CheckResult (CompilerEnv, Module)
typeClassesCheck env (Module m es is ds) 
  | null msgs = CheckSuccess (env {classEnv = clsEnv}, Module m es is decls') 
  | otherwise = CheckFailed msgs
  where (decls', clsEnv, msgs) = TCC.typeClassesCheck m ds (classEnv env) (tyConsEnv env)


