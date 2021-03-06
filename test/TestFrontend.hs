--------------------------------------------------------------------------------
-- Test Suite for the Curry Frontend
--------------------------------------------------------------------------------
--
-- This Test Suite supports three kinds of tests:
--
-- 1) tests which should pass
-- 2) tests which should pass with a specific warning
-- 3) tests which should fail yielding a specific error message
--
-- In order to add a test to this suite, proceed as follows:
--
-- 1) Store your test code in a file (please use descriptive names) and put it
--    in the corresponding subfolder (i.e. test/pass for passing tests,
--    test/fail for failing tests and test/warning for passing tests producing
--    warnings)
-- 2) Extend the corresponding test information list (there is one for each test
--    group at the end of this file) with the required information (i.e. name of
--    the Curry module to be tested and expected warning/failure message(s))
-- 3) Run 'cabal test'

{-# LANGUAGE CPP #-}
module TestFrontend (tests) where

#if __GLASGOW_HASKELL__ < 710
import           Control.Applicative    ((<$>))
#endif
import qualified Control.Exception as E (SomeException, catch)

import           Data.List              (isInfixOf, sort)
import           Distribution.TestSuite
import           System.FilePath        (FilePath, (</>), (<.>))

import           Curry.Base.Message     (Message, message, ppMessages, ppError)
import           Curry.Base.Monad       (CYIO, runCYIO)
import           Curry.Base.Pretty      (text)
import qualified CompilerOpts as CO     ( Options (..), WarnOpts (..)
                                        , WarnFlag (..), Verbosity (VerbQuiet)
                                        , defaultOptions, defaultWarnOpts)
import CurryBuilder                     (buildCurry)

tests :: IO [Test]
tests = return [passingTests, warningTests, failingTests]

runSecure :: CYIO a -> IO (Either [Message] (a, [Message]))
runSecure act = runCYIO act `E.catch` handler
  where handler e = return (Left [message $ text $ show (e :: E.SomeException)])

-- Execute a test by calling cymake
runTest :: CO.Options -> String -> [String] -> IO Progress
runTest opts test [] = passOrFail <$> runSecure (buildCurry opts' test)
 where
  wOpts         = CO.optWarnOpts opts
  wFlags        =   CO.WarnUnusedBindings
                  : CO.WarnUnusedGlobalBindings
                  : CO.wnWarnFlags wOpts
  opts'         = opts { CO.optForce    = True
                       , CO.optWarnOpts = wOpts { CO.wnWarnFlags = wFlags }
                       }
  passOrFail    = Finished . either fail pass
  fail msgs
    | null msgs = Pass
    | otherwise = Fail $ "An unexpected failure occurred: " ++ showMessages msgs
  pass _        = Pass
runTest opts test errorMsgs = catchE <$> runSecure (buildCurry opts' test)
 where
  wOpts         = CO.optWarnOpts opts
  wFlags        =   CO.WarnUnusedBindings
                  : CO.WarnUnusedGlobalBindings
                  : CO.wnWarnFlags wOpts
  opts'         = opts { CO.optForce    = True
                       , CO.optWarnOpts = wOpts { CO.wnWarnFlags = wFlags }
                       }
  catchE        = Finished . either pass fail
  pass msgs = let errorStr     = showMessages msgs
                  leftOverMsgs = filter (not . flip isInfixOf errorStr) errorMsgs
               in if null leftOverMsgs
                 then Pass
                 else Fail $ "Expected warnings/failures did not occur: " ++ unwords leftOverMsgs
  fail          = pass . snd

showMessages :: [Message] -> String
showMessages = show . ppMessages ppError . sort

-- group of tests which should pass
passingTests :: Test
passingTests = Group { groupName    = "Passing Tests"
                     , concurrently = False
                     , groupTests   = map (mkTest "test/pass/") passInfos
                     }

-- group of test which should fail yielding a specific error message
failingTests :: Test
failingTests = Group { groupName    = "Failing Tests"
                     , concurrently = False
                     , groupTests   = map (mkTest "test/fail/") failInfos
                     }

-- group of tests which should pass producing a specific warning message
warningTests :: Test
warningTests = Group { groupName    = "Warning Tests"
                     , concurrently = False
                     , groupTests   = map (mkTest "test/warning/") warnInfos
                     }

-- create a new test
mkTest :: FilePath -> TestInfo -> Test
mkTest path (testName, testTags, testOpts, mSetOpts, errorMsgs) =
  let file = path </> testName <.> "curry"
      opts = CO.defaultOptions { CO.optVerbosity   = CO.VerbQuiet
                               , CO.optImportPaths = [path]
                               }
      test = TestInstance
        { run       = runTest opts file errorMsgs
        , name      = testName
        , tags      = testTags
        , options   = testOpts
        , setOption = maybe (\_ _ -> Right test) id mSetOpts
        }
  in Test test

-- Information for a test instance:
-- * name of test
-- * tags to classify a test
-- * options
-- * function to set options
-- * optional warning/error message which should be thrown on execution of test
type TestInfo = (String, [String], [OptionDescr], Maybe SetOption, [String])

type SetOption = String -> String -> Either String TestInstance

--------------------------------------------------------------------------------
-- Definition of passing tests
--------------------------------------------------------------------------------

-- generate a simple passing test
mkPassTest :: String -> TestInfo
mkPassTest name = (name, [], [], Nothing, [])

-- To add a passing test to the test suite simply add the module name of the
-- test code to the following list
passInfos :: [TestInfo]
passInfos = map mkPassTest
  [ "AbstractCurryBug"
  , "ACVisibility"
  , "AnonymVar"
  , "CaseComplete"
  , "DefaultPrecedence"
  , "Dequeue"
  , "ExplicitLayout"
  , "FCase"
  , "FP_Lifting"
  , "FP_NonCyclic"
  , "FP_NonLinearity"
  , "FunctionalPatterns"
  , "HaskellRecords"
  , "Hierarchical"
  , "Infix"
  , "Inline"
  , "Lambda"
  , "Maybe"
  , "NegLit"
  , "Newtype1"
  , "Newtype2"
  , "NonLinearLHS"
  , "OperatorDefinition"
  , "PatDecl"
  , "Prelude"
  , "Pretty"
  , "RecordsPolymorphism"
  , "RecordTest1"
  , "RecordTest2"
  , "RecordTest3"
  , "ReexportTest"
  , "SelfExport"
  , "SpaceLeak"
  , "TyConsTest"
  , "TypedExpr"
  , "UntypedAcy"
  , "Unzip"
  ]

--------------------------------------------------------------------------------
-- Definition of failing tests
--------------------------------------------------------------------------------

-- generate a simple failing test
mkFailTest :: String -> [String] -> TestInfo
mkFailTest name errorMsgs = (name, [], [], Nothing, errorMsgs)

-- To add a failing test to the test suite simply add the module name of the
-- test code and the expected error message(s) to the following list
failInfos :: [TestInfo]
failInfos = map (uncurry mkFailTest)
  [ ("ErrorMultipleSignature", ["More than one type signature for `f'"])
  , ("ExportCheck/AmbiguousName", ["Ambiguous name `not'"])
  , ("ExportCheck/AmbiguousType", ["Ambiguous type `Bool'"])
  , ("ExportCheck/ModuleNotImported", ["Module `Foo' not imported"])
  , ("ExportCheck/MultipleName", ["Multiple exports of name `not'"])
  , ("ExportCheck/MultipleType", ["Multiple exports of type `Bool'"])
  , ("ExportCheck/NoDataType", ["`Foo' is not a data type"])
  , ("ExportCheck/OutsideTypeConstructor", ["Data constructor `False' outside type export in export list"])
  , ("ExportCheck/OutsideTypeLabel", ["Label `value' outside type export in export list"])
  , ("ExportCheck/UndefinedElement", ["`foo' is not a constructor or label of type `Bool'"])
  , ("ExportCheck/UndefinedName", ["Undefined name `foo' in export list"])
  , ("ExportCheck/UndefinedType", ["Undefined type `Foo' in export list"])
  , ("FP_Cyclic", ["Function `g' used in functional pattern depends on `f'  causing a cyclic dependency"])
  , ("FP_Restrictions",
      [ "Functional patterns are not supported inside a case expression"
      , "Functional patterns are not supported inside a case expression"
      , "Functional patterns are not supported inside a list comprehension"
      , "Functional patterns are not supported inside a do sequence"
      ]
    )
  , ("FP_NonGlobal", ["Function `f1' in functional pattern is not global"])
  , ("ImportError",
      [ "Module Prelude does not export foo"
      , "Module Prelude does not export bar"
      ]
    )
  , ("KindCheck",
      [ "Type variable a occurs more than once on left hand side of type declaration"
      , "Type variable b occurs more than once on left hand side of type declaration"
      ]
    )
  , ("MultipleArities", ["Equations for `test' have different arities"])
  , ("MultipleDefinitions",
      ["Multiple definitions for data/record constructor `Rec'"]
    )
  , ("MultiplePrecedence",
      ["More than one fixity declaration for `f'"]
    )
  , ("PatternRestrictions",
      [ "Lazy patterns are not supported inside a functional pattern"]
    )
  , ("PragmaError", ["Unknown language extension"])
  , ("PrecedenceRange", ["Precedence out of range"])
  , ("RecordLabelIDs", ["Multiple declarations of `RecordLabelIDs.id'"])
  , ("RecursiveTypeSyn", ["Recursive synonym types A and B"])
  , ("SyntaxError", ["Type error in application"])
  , ("TypedFreeVariables",
      ["Free variable x has a polymorphic type", "Type signature too general"]
    )
  , ("TypeError1",
      [ "Type error in explicitly typed expression"
      , "Type signature too general"
      ]
    )
  , ("TypeError2", ["Type error in infix application"])
  ]

--------------------------------------------------------------------------------
-- Definition of warning tests
--------------------------------------------------------------------------------

-- To add a warning test to the test suite simply add the module name of the
-- test code and the expected warning message(s) to the following list
warnInfos :: [TestInfo]
warnInfos = map (uncurry mkFailTest)
  [
    ("AliasClash",
      [ "The module alias `AliasClash' overlaps with the current module name"
      , "Overlapping module aliases"
      , "Module List is imported more than once"
      ]
    )
  , ("Case1", ["Pattern matches are non-exhaustive", "In an equation for `h'"])
  , ("Case2",
      [ "An fcase expression is non-deterministic due to overlapping rules"
      , "Pattern matches are non-exhaustive", "In an fcase alternative"
      , "In a case alternative", "In an equation for `fp'"
      , "Pattern matches are unreachable"
      , "Function `fp' is non-deterministic due to overlapping rules"
      , "Pattern matches are non-exhaustive"
      ]
    )
  , ("CheckSignature",
      [ "Top-level binding with no type signature: hw"
      , "Top-level binding with no type signature: f"
      , "Unused declaration of variable `answer'"
      ]
    )
  , ("NonExhaustivePattern",
      [ "Pattern matches are non-exhaustive", "In a case alternative"
      , "In an equation for `test2'", "In an equation for `and'"
      , "In an equation for `plus'", "In an equation for `len2'"
      , "In an equation for `tuple'", "In an equation for `tuple2'"
      , "In an equation for `g'", "In an equation for `rec'"]
    )
  , ("OverlappingPatterns",
      [ "Pattern matches are unreachable", "In a case alternative"
      , "An fcase expression is non-deterministic due to overlapping rules"
      , "Function `i' is non-deterministic due to overlapping rules"
      , "Function `j' is non-deterministic due to overlapping rules"
      , "Function `k' is non-deterministic due to overlapping rules"
      ]
    )
  , ("ShadowingSymbols",
      [ "Unused declaration of variable `x'", "Shadowing symbol `x'"])
  , ("TabCharacter",
      [ "Tab character"])
  , ("UnexportedFunction",
      [ "Unused declaration of variable `q'"
      , "Unused declaration of variable `g'" ]
    )
  ]
