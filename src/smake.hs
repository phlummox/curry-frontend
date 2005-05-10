-------------------------------------------------------------------------------
-------------------------------------------------------------------------------
--
-- smake - A simple command line make tool
--
--
-- Usage:  
--     smake <targets> : <dependencies> [: <rule>]
--
-- Executes <rule>, if any file in <dependencies> is newer than any file
-- in <targets> or if any file in <targets> doesn't exisit. The result
-- of smake is the result of the execution of <rule>.
--
-- Without specifying <rule> smake can be used to check the out-of-dateness
-- between the files in <targets> and the files in <dependencies>.
-- smake returns 1, if any file in <dependencies> is newer than any file
-- in <targets> or if any file in <targets> doesn't exisit, and otherwise 0.
--
-- If smake failes on any reason, the returned error code is 2.
--
-- May 2005,
-- Martin Engelke (men@informatik.uni-kiel.de)
--

import System
import Directory
import Time
import Monad
import Maybe


-------------------------------------------------------------------------------

main :: IO ()
main = do prog <- getProgName
	  args <- getArgs
	  opts <- parseArgs args
          when (null (targets opts)) (badUsage prog "missing targets")
          when (null (deps opts)) (badUsage prog "missing dependencies")
	  code <- smake opts
	  exitWith code


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------

smake :: Options -> IO ExitCode
smake opts
   = do tgtimes <- getTargetTimes (targets opts)
	dptimes <- getDepTimes (deps opts)
	checkTimes tgtimes dptimes
 where
   checkTimes tgtimes dptimes
      | (length tgtimes) < (length (targets opts))
	= maybe (return (ExitFailure 1))
                execRule
		(rule opts) --execRule (fromMaybe "" (rule opts)) >>= return
      | null dptimes 
	= return (ExitFailure 2)
      | outOfDate tgtimes dptimes 
	= maybe (return (ExitFailure 1))
                execRule
		(rule opts) --execRule (fromMaybe "" (rule opts)) >>= return
      | otherwise
        = return ExitSuccess


getTargetTimes :: [String] -> IO [ClockTime]
getTargetTimes [] = return []
getTargetTimes (f:fs)
   = catch (do t  <- getModificationTime f
	       ts <- getTargetTimes fs
	       return (t:ts))
           (const (getTargetTimes fs))


getDepTimes :: [String] -> IO [ClockTime]
getDepTimes [] = return []
getDepTimes (f:fs)
   = catch (do t  <- getModificationTime f
	       ts <- getDepTimes fs
	       return (t:ts))
           (\err -> putStrLn (show err) >> return [])


execRule :: String -> IO ExitCode
execRule rule | null rule = return ExitSuccess
	      | otherwise = system rule >>= return


outOfDate :: [ClockTime] -> [ClockTime] -> Bool
outOfDate tgtimes dptimes = or (map (\t -> or (map ((<) t) dptimes)) tgtimes)


-------------------------------------------------------------------------------

data Options = Options { targets :: [FilePath],
			 deps    :: [FilePath],
			 rule    :: Maybe String
		       }


parseArgs :: [String] -> IO Options
parseArgs args = return Options { targets = ts,
				  deps    = ds,
				  rule    = mrs
				}
 where
   (ts, args')  = span ((/=) ":") args
   (ds, args'') = span ((/=) ":") (rest args')
   rs           = rest (args'')
   mrs          | null rs   = Nothing
		| otherwise = Just (unwords rs)


-------------------------------------------------------------------------------

badUsage :: String -> String -> IO ()
badUsage prog reason = do putStrLn ("Fail: " ++ reason)
			  putStrLn ("Usage: " ++ prog
				    ++ " <targets>"
				    ++ " : <dependencies>"
				    ++ " [: <rule>]")
			  exitWith (ExitFailure 2)


-------------------------------------------------------------------------------

rest []     = []
rest (_:xs) = xs


-------------------------------------------------------------------------------
-------------------------------------------------------------------------------