{- |
    Module      :  $Header$
    Description :  Main module
    Copyright   :  (c) 2005        Martin Engelke
                       2011 - 2014 Björn Peemöller
    License     :  OtherLicense

    Maintainer  :  bjp@informatik.uni-kiel.de
    Stability   :  experimental
    Portability :  portable

    Command line tool for generating Curry representations (e.g. FlatCurry,
    AbstractCurry) for a Curry source file including all imported modules.
-}
module Main (main) where

import Curry.Base.Monad (runCYIO)

import Base.Messages
import Files.CymakePath (cymakeGreeting, cymakeVersion)
import Html.CurryHtml   (source2html)
--import Token.WriteToken.hs (source2token)

import CurryBuilder (buildCurry)
import CompilerOpts (Options (..), CymakeMode (..), getCompilerOpts, usage)

-- |The command line tool cymake
main :: IO ()
main = getCompilerOpts >>= cymake

-- |Invoke the curry builder w.r.t the command line arguments
cymake :: (String, Options, [String], [String]) -> IO ()
cymake (prog, opts, files, errs)
  | mode == ModeHelp           = printUsage prog
  | mode == ModeVersion        = printVersion
  | mode == ModeNumericVersion = printNumericVersion
  | not $ null errs            = badUsage prog errs
  | null files                 = badUsage prog ["no input files"]
  | mode == ModeHtml           =
    runCYIO (mapM_ (source2html opts) files) >>= okOrAbort
  -- | mode == ModeToken          =
  --  runCYIO (mapM_ (source2token opts) files) >>= okOrAbort
  | otherwise                  =
    runCYIO (mapM_ (buildCurry  opts) files) >>= okOrAbort
  where mode = optMode opts
        okOrAbort = either abortWithMessages return

-- |Print the usage information of the command line tool
printUsage :: String -> IO ()
printUsage prog = putStrLn $ usage prog

-- |Print the program version
printVersion :: IO ()
printVersion = putStrLn cymakeGreeting

-- |Print the numeric program version
printNumericVersion :: IO ()
printNumericVersion = putStrLn cymakeVersion

-- |Print errors and abort execution on bad parameters
badUsage :: String -> [String] -> IO ()
badUsage prog errs = do
  putErrsLn $ map (\ err -> prog ++ ": " ++ err) errs
  abortWith ["Try '" ++ prog ++ " --help' for more information"]
