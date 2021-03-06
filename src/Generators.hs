{- |
    Module      :  $Header$
    Description :  Code generators
    Copyright   :  (c) 2011, Björn Peemöller (bjp@informatik.uni-kiel.de)
    License     :  BSD-3-clause

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable

    This module subsumes the different code generators.
-}
module Generators where

import qualified Curry.AbstractCurry         as AC  (CurryProg)
import qualified Curry.ExtendedFlat.Type     as EF  (Prog)
import qualified Curry.Syntax                as CS  (Module, Interface)

import qualified Generators.GenAbstractCurry as GAC (genAbstractCurry)
import qualified Generators.GenFlatCurry     as GFC (genFlatCurry, genFlatInterface)

import           CompilerEnv                        (CompilerEnv (..))
import qualified IL                                 (Module)

-- |Generate typed AbstractCurry
genTypedAbstractCurry :: CompilerEnv -> CS.Module -> AC.CurryProg
genTypedAbstractCurry = GAC.genAbstractCurry False

-- |Generate untyped AbstractCurry
genUntypedAbstractCurry :: CompilerEnv -> CS.Module -> AC.CurryProg
genUntypedAbstractCurry = GAC.genAbstractCurry True

-- |Generate FlatCurry
genFlatCurry :: CompilerEnv -> CS.Module -> IL.Module -> EF.Prog
genFlatCurry = GFC.genFlatCurry

-- |Generate a FlatCurry interface
genFlatInterface :: CompilerEnv -> CS.Interface -> CS.Module -> IL.Module -> EF.Prog
genFlatInterface = GFC.genFlatInterface
