-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--
-- cymake - The Curry builder
--
--          Command line tool for generating Curry representations (e.g.
--          FlatCurry, AbstractCurry) for a Curry source file including
--          all imported modules.
--
-- September 2005,
-- Martin Engelke (men@informatik.uni-kiel.de)
--

module Main(main) where

import Data.List
import Data.Maybe
import System.IO
import System.Environment
import System.Exit
import Control.Monad (unless)
import Data.Char (isDigit)

import GetOpt
import CurryBuilder
import CurryCompilerOpts
import CurryHtml

-------------------------------------------------------------------------------

-- The command line tool.
main :: IO ()
main = do prog    <- getProgName
	  args    <- getArgs
	  cymake prog args 


-------------------------------------------------------------------------------

-- Checks the command line arguments and invokes the builder.
cymake :: String -> [String] -> IO ()
cymake prog args 
   | elem Help opts = printUsage prog
   | null files     = badUsage prog ["no files"]
   | null errs' && not (elem Html opts)    = do
       unless (noVerb options') 
              (putStrLn  $ "This is cymake, version 1.1." 
                         ++ filter isDigit "$Revision$")
       mapM_ (buildCurry options') files
   | null errs' = do
      let importFiles = nub $ importPaths opts'
          outputFile  = maybe "" id (output opts')
      mapM_ (source2html importFiles outputFile) files
                              
   | otherwise      = badUsage prog errs'
 where
 (opts, files, errs) = getOpt Permute options args
 opts'    = foldr selectOption defaultOpts opts
 options' = if  flat opts' || flatXml opts' 
	        || abstract opts' || untypedAbstract opts' || parseOnly opts'
	        then  opts'
	        else  opts'{ flat = True }
 errs'    = errs ++ check options' files


-- Prints usage information of the command line tool.
printUsage :: String -> IO ()
printUsage prog
   = do putStrLn (usageInfo header options)
	exitWith ExitSuccess
 where
 header = "usage: " ++ prog ++ " [OPTION] ... MODULE ..."


-- Prints errors
badUsage :: String -> [String] -> IO ()
badUsage prog errs
   = do mapM (\err -> putErrLn (prog ++ ": " ++ err)) errs
	abortWith ["Try '" ++ prog ++ " -" ++ "-help' for more information"]


-- Checks options and files.
check :: Options -> [String] -> [String]
check opts files
   | null files 
     = ["no files"]
   | isJust (output opts) && length files > 1
     = ["cannot specify -o with multiple targets"]
   | otherwise
     = []


-------------------------------------------------------------------------------
-- Error handling

-- Prints an error message on 'stderr'
putErrLn :: String -> IO ()
putErrLn = hPutStrLn stderr

-- Prints a list of error messages on 'stderr'
putErrsLn :: [String] -> IO ()
putErrsLn = mapM_ putErrLn

-- Prints a list of error messages on 'stderr' and aborts the program
abortWith :: [String] -> IO a
abortWith errs = putErrsLn errs >> exitWith (ExitFailure 1)


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
