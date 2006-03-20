module SyntaxColoring where


--(module SyntaxColoring, parseString,main) where

import System.Environment
import CurryLexer
import Position
import Frontend
import Ident
import CurrySyntax 
import Char
import Maybe
import List
import Debug.Trace
import Message
import Control.Exception


debug = False  --True

trace' s x = if debug then trace s x else x


debug' = True

trace'' s x = if debug' then trace s x else x

data Program = Program ModuleIdent [Code] deriving Show

data Code =  Keyword String
           | Space Int
           | NewLine
           | ConstructorName  ConstructorKind QualIdent
           | TypeConstructor  TypeKind QualIdent
           | Function FunctionKind QualIdent
           | ModuleName ModuleIdent
           | Commentary String
           | NumberCode String
           | StringCode String
           | CharCode String
           | Symbol String
           | Identifier IdentifierKind QualIdent
           | CodeWarning [Message] [Code]
           | CodeError [Message] [Code]
           | NotParsed String deriving Show
           
data TypeKind = TypeDecla
              | TypeUse deriving Show          

data ConstructorKind = ConstrPattern
                     | ConstrCall
                     | ConstrDecla
                     | OtherConstrKind deriving Show
                     
data IdentifierKind = IdDecl
                    | IdOccur
                    | UnknownId  deriving Show         
                      
data FunctionKind = InfixFunction
                  | TypSig
                  | FunDecl
                  | FunctionCall
                  | OtherFunctionKind deriving Show           
                  
-- DEBUGGING----------- wird bald nicht mehr gebraucht

setMessagePosition :: Message -> Message
setMessagePosition m@(Message _ (Just p) _) = trace'' ("pos:" ++ show p ++ ":" ++ show m) m
setMessagePosition (Message typ _ m) = 
        let mes@(Message _ pos _) =  (Message typ (getPositionFromString m) m) in
        trace'' ("pos:" ++ show pos ++ ":" ++ show mes) mes

getPositionFromString :: String -> Maybe Position
getPositionFromString message =
     if line > 0 && col > 0 
          then Just (Position file line col)
          else Nothing 
  where
      file = takeWhile (/= '"') (tail (dropWhile (/= '"') message))
      line = readInt (takeWhile (/= '.') (drop 7 (dropWhile (/= ',') message)))
      col = readInt (takeWhile (/= ':') (tail (dropWhile (/= '.') (drop 7 (dropWhile (/= ',') message)))))
      
     
readInt :: String -> Int 
readInt s = 
      let onlyNum = filter isDigit s in
      if null onlyNum
         then 0
         else read onlyNum :: Int

-- -------------------------

catchError :: IO (Result a) -> IO (Result a)
catchError toDo = Control.Exception.catch toDo handler 
  where
      handler (ErrorCall str) = return (Failure [setMessagePosition (Message Error Nothing str)])
      handler  e = return (Failure [Message Error Nothing (show e)])
      file str = takeWhile (/= '"') (tail str)

t :: IO (Result Char)      
t = return (Result [] (head ""))
      
      
-- -------------------------


flatCode :: Code -> [Code]
flatCode (CodeWarning _ codes) = concatMap flatCode codes
flatCode (CodeError _ codes) = concatMap flatCode codes
flatCode code = [code]
             

                 
-- ----------Message---------------------------------------                  
                  

getMessages :: Result a -> [Message]
getMessages (Result mess _) = mess
getMessages (Failure mess) = mess

lessMessage :: Message -> Message -> Bool
lessMessage (Message _ mPos1 _) (Message _ mPos2 _) = mPos1 < mPos2

nubMessages :: [Message] -> [Message] 
nubMessages = nubBy eqMessage

eqMessage :: Message -> Message -> Bool
eqMessage (Message f1 p1 s1) (Message f2 p2 s2) = (f1 == f2) && (p1 == p2) && (s1 == s2)

prepareMessages :: [Message] -> [Message]   
prepareMessages = qsort lessMessage . map setMessagePosition . nubMessages

hasError [] = False
hasError ((Message Error _ _):ms) = True
hasError (_:ms) = hasError ms

buildMessagesIntoPlainText :: [Message] -> String -> [Code]
buildMessagesIntoPlainText messages text = 
    buildMessagesIntoPlainText' messages (lines text) [] 1
 where
    buildMessagesIntoPlainText' :: [Message] -> [String] -> [String] -> Int -> [Code]
    buildMessagesIntoPlainText' _ [] [] _ = 
          []
    buildMessagesIntoPlainText' _ [] postStrs _ = 
          [NotParsed (unlines postStrs)]    
    buildMessagesIntoPlainText' [] preStrs postStrs _ = 
          [NotParsed (unlines (preStrs ++ postStrs))]  
            
    buildMessagesIntoPlainText' messages (str:preStrs) postStrs line = 
          let (pre,post) = partition isLeq messages in
          if null pre 
             then buildMessagesIntoPlainText' post preStrs (postStrs ++ [str]) (line + 1)
             else (NotParsed (unlines postStrs)) : 
                  (if hasError pre then (CodeError pre [NotParsed str,NewLine]) 
                                   else (CodeWarning pre [NotParsed str,NewLine])) :
                  (buildMessagesIntoPlainText' post preStrs [] (line + 1)) 
      where 
         isLeq (Message _ (Just (Position _ l _)) _) = l <= line 
         isLeq _ = True
                

   
--- muss noch vereinfacht werden!!
filename2program :: String -> IO Program
filename2program filename =
     readFile filename >>= \ cont ->
     (catchError (return (parse filename cont))) >>= \ parseResult ->
     (catchError (return (Frontend.lex filename cont))) >>= \ lexResult ->  
     return (genQualifiedProgram cont (Failure []) parseResult lexResult) 

                            
filename2Qualifiedprogram :: [String] -> String -> IO Program
filename2Qualifiedprogram paths filename=
     readFile filename >>= \ cont ->
     (catchError (typingParse paths filename  cont)) >>= \ typingParseResult ->           
     (catchError (return (parse filename cont))) >>= \ parseResult ->
     (catchError (return (Frontend.lex filename cont))) >>= \ lexResult ->    
     return (genQualifiedProgram cont typingParseResult parseResult lexResult)    
                        

genProgram :: String -> Result Module -> Result [(Position,Token)] -> Program
genProgram plainText = genQualifiedProgram plainText (Failure [])       
          
--- muss noch vereinfacht werden!!
--- @param typingParse-Module 
--- @param parse-Module
--- @param lex-Result
genQualifiedProgram :: String -> Result Module -> Result Module -> Result [(Position,Token)] -> Program 
genQualifiedProgram  plainText
                     typParseResult@(Result _ _) 
                     parseResult@(Result _ (Module  moduleIdent _ _))                      
                     lexResult = 
      Program moduleIdent
              (replaceFunctionCalls 
                    (map (addModuleIdent moduleIdent)                     
                         (genQualifiedCode plainText typParseResult parseResult  lexResult)))
                  
genQualifiedProgram  plainText
                     typParseResult@(Failure _)
                     parseResult@(Result _ (Module  moduleIdent _ _))                      
                     lexResult = 
      trace' (show typParseResult)  $               
      Program moduleIdent
              (genQualifiedCode plainText typParseResult parseResult  lexResult)
                 
genQualifiedProgram plainText typParseResult parseResult lexResult =
      trace' (show parseResult)  $
      Program (mkMIdent [])
              (genQualifiedCode plainText typParseResult parseResult  lexResult)
              
              

genCode :: String -> Result Module -> Result [(Position,Token)] -> [Code]
genCode plainText = genQualifiedCode plainText (Failure [])
           
           
--- @param typingParse-Module                             
--- @param parse-Module             

genQualifiedCode :: String -> Result Module ->  Result Module -> Result [(Position,Token)] -> [Code]       
genQualifiedCode _ typParseResult parseResult (Result mess posNtokList) = 
    let messages = (prepareMessages 
                      (getMessages typParseResult ++ 
                       getMessages parseResult ++ 
                       mess))
        mergedMessages = (mergeMessages' (trace' ("Messages: " ++ show messages) messages) 
                                      posNtokList) in
    tokenNcodes2codes 1 
                      1
                      mergedMessages 
                      (catQualifiedIdentifiers typParseResult parseResult)            

    
genQualifiedCode plainText typParseResult parseResult (Failure messages3) =
     trace' (unlines (map (\(Message _ _ str) -> str) allMessages)) (buildMessagesIntoPlainText allMessages plainText)    
  where
      allMessages = prepareMessages (getMessages typParseResult ++ 
                                            getMessages parseResult ++ 
                                            messages3)   
     
    
catIdentifiers :: Result Module -> [Code]
catIdentifiers  =  catQualifiedIdentifiers (Failure [])               

--- @param typingParse-Module  
--- @param parse-Module   
catQualifiedIdentifiers :: Result Module -> Result Module -> [Code]
catQualifiedIdentifiers (Failure _) parseResult@(Result _ _)  =
     catQualifiedIdentifiers parseResult parseResult   
catQualifiedIdentifiers typParseResult@(Result _ _) (Failure _)  =
     catQualifiedIdentifiers typParseResult typParseResult           
catQualifiedIdentifiers (Failure _) (Failure _)  = []
catQualifiedIdentifiers (Result _ (Module  _ _ typingDecls))
                        (Result _ (Module  moduleIdent maybeExportSpec _)) =
     let codes = concatMap decl2codes (qsort lessDecl typingDecls) in                   
     ([ModuleName moduleIdent] ++
     (maybe [] (exportSpec2codes (filterTypeDecla codes)) maybeExportSpec)  ++
     codes)     
  where
     filterTypeDecla [] = []
     filterTypeDecla ((TypeConstructor TypeDecla qualIdent):xs) = qualIdent : filterTypeDecla xs
     filterTypeDecla (_:xs) =  filterTypeDecla xs
       

                      
replaceFunctionCalls :: [Code] -> [Code]                  
replaceFunctionCalls codes = map (idOccur2functionCall qualIdents) codes
   where
      qualIdents = findFunctionDecls codes
                                              

findFunctionDecls :: [Code] -> [QualIdent]
findFunctionDecls  =  mapMaybe getQualIdent . filter isFunctionDecl . concatMap flatCode                   

isFunctionDecl  :: Code -> Bool
isFunctionDecl  (Function FunDecl _)  = True
isFunctionDecl  _ = False  

idOccur2functionCall :: [QualIdent] -> Code -> Code
idOccur2functionCall qualIdents ide@(Identifier IdOccur qualIdent)  
   | isQualified qualIdent = (Function FunctionCall qualIdent)
   | elem qualIdent qualIdents = (Function FunctionCall qualIdent)
   | otherwise = ide
idOccur2functionCall qualIdents (CodeWarning mess codes) =
       (CodeWarning mess (map (idOccur2functionCall qualIdents) codes))
idOccur2functionCall qualIdents (CodeError mess codes) =
       (CodeError mess (map (idOccur2functionCall qualIdents) codes))       
idOccur2functionCall _ code = code
  

addModuleIdent :: ModuleIdent -> Code -> Code
addModuleIdent moduleIdent (Function x qualIdent) 
    | uniqueId (unqualify qualIdent) == 0 =
        (Function x (qualQualify moduleIdent qualIdent))
    | otherwise = (Function x qualIdent)   
addModuleIdent moduleIdent cn@(ConstructorName x qualIdent) 
    | not $ isQualified qualIdent =
        (ConstructorName x (qualQualify moduleIdent qualIdent)) 
    | otherwise = cn       
addModuleIdent moduleIdent tc@(TypeConstructor TypeDecla qualIdent) 
    | not $ isQualified qualIdent =
        (TypeConstructor TypeDecla (qualQualify moduleIdent qualIdent)) 
    | otherwise = tc         
addModuleIdent moduleIdent (CodeWarning mess codes) =
      (CodeWarning mess (map (addModuleIdent moduleIdent) codes))   
addModuleIdent moduleIdent (CodeError mess codes) =
      (CodeError mess (map (addModuleIdent moduleIdent) codes))       
addModuleIdent _ c = c
                        
-- ----------------------------------------

mergeMessages :: [Message] -> [(Position,Token)] -> [([Message],Position,Token)]
mergeMessages mess pos = mergeMessages' (prepareMessages mess) pos



mergeMessages' :: [Message] -> [(Position,Token)] -> [([Message],Position,Token)]
mergeMessages' _ [] = []
mergeMessages' [] ((p,t):ps) = ([],p,t) : mergeMessages' [] ps
mergeMessages' mss@(m@(Message _ mPos x):ms) ((p,t):ps)  
    | mPos <= Just p = (trace' (show mPos ++ " <= " ++ show (Just p) ++ " Message: " ++ x) ([m],p,t)) : mergeMessages' ms ps 
    | otherwise = ([],p,t) : mergeMessages' mss ps


tokenNcodes2codes :: Int -> Int -> [([Message],Position,Token)] -> [Code] -> [Code]
tokenNcodes2codes _ _ [] _ = []          
tokenNcodes2codes currLine currCol toks@((messages,pos@(Position _ line col),token):ts) codes 
    | currLine < line = 
           trace' (" NewLine: ")
           (NewLine :
           tokenNcodes2codes (currLine + 1) 1 toks codes)
    | currCol < col =  
           trace' (" Space " ++ show (col - currCol))
           (Space (col - currCol) :         
           tokenNcodes2codes currLine col toks codes)
    | isTokenIdentifier token && null codes =    
           trace' ("empty Code-List, Token: " ++ show (line,col) ++ show token)
           (addMessage [NotParsed tokenStr] ++ tokenNcodes2codes newLine newCol ts codes)
    | not (isTokenIdentifier token) = 
           trace' (" Token ist kein Identifier: " ++ tokenStr ) 
           (addMessage [token2code token] ++ tokenNcodes2codes newLine newCol ts codes) 
    | tokenStr == code2string (head codes) =
           trace' (" Code wird genommen: " ++ show (head codes) )
           (addMessage [head codes] ++ tokenNcodes2codes newLine newCol ts (tail codes)) 
    | tokenStr == code2qualString (head codes) =
           let prefix = maybe [] ((: [Symbol "."]) . ModuleName) (getModuleIdent (head codes)) in
           trace' (" Code wird genommen: " ++ show (head codes) )
           (addMessage (prefix ++ [head codes]) ++ tokenNcodes2codes newLine newCol ts (tail codes))           
    | elem tokenStr (codeQualifiers (head codes)) =
           trace' (" Token: "++ tokenStr ++" ist Modulname von: " ++ show (head codes) )
           (addMessage [ModuleName (mkMIdent [tokenStr])] ++ 
                    tokenNcodes2codes newLine newCol ts codes)                  
    | otherwise = 
           trace' (" Token: "++ 
                   tokenStr ++
                   ",Code f�llt weg:" ++ 
                   code2string (head codes) ++ 
                   "|" ++ 
                   code2qualString (head codes))
           (tokenNcodes2codes currLine currCol toks (tail codes))
  where
      tokenStr = token2string token            
      newLine  = (currLine + length (lines tokenStr)) - 1 
      newCol   = currCol + length tokenStr    

      addMessage codes
         | null messages = codes
         | hasError messages = trace' ("Error bei code: " ++ show codes ++ ":" ++ show messages) [CodeError messages codes]
         | otherwise = trace' ("Warning bei code: " ++ show codes ++ ":" ++ show messages) [CodeWarning  messages codes]
      
      

           
{-
codeWithoutUniqueID ::  Code -> String
codeWithoutUniqueID code = maybe (code2string code) (name . unqualify) $ getQualIdent code
     

codeUnqualify :: Code -> Code
codeUnqualify code = maybe code (setQualIdent code . qualify . unqualify)  $ getQualIdent code  
-}  
          
codeQualifiers :: Code -> [String]
codeQualifiers = maybe [] moduleQualifiers . getModuleIdent

getModuleIdent :: Code -> Maybe ModuleIdent
getModuleIdent (ConstructorName _ qualIdent) = fst $ splitQualIdent qualIdent
getModuleIdent (Function _ qualIdent) = fst $ splitQualIdent qualIdent
getModuleIdent (ModuleName moduleIdent) = Just moduleIdent
getModuleIdent (Identifier _ qualIdent) = fst $ splitQualIdent qualIdent                     
getModuleIdent (TypeConstructor _ qualIdent) = fst $ splitQualIdent qualIdent
getModuleIdent _ = Nothing

getQualIdent :: Code -> Maybe QualIdent
getQualIdent (ConstructorName _ qualIdent) = Just qualIdent
getQualIdent (Function _ qualIdent) = Just qualIdent
getQualIdent (Identifier _ qualIdent) = Just qualIdent                      
getQualIdent (TypeConstructor _ qualIdent) = Just qualIdent
getQualIdent  _ = Nothing
  
{-
setQualIdent :: Code -> QualIdent -> Code
setQualIdent (Keyword str) _ = (Keyword str)
setQualIdent (Space i) _ = (Space i)
setQualIdent NewLine _ = NewLine
setQualIdent (ConstructorName kind _) qualIdent = (ConstructorName kind qualIdent)
setQualIdent (Function kind _) qualIdent = (Function kind qualIdent)
setQualIdent (ModuleName moduleIdent) _ = (ModuleName moduleIdent)
setQualIdent (Commentary str) _ = (Commentary str)
setQualIdent (NumberCode str) _ = (NumberCode str)
setQualIdent (Symbol str) _ = (Symbol str)
setQualIdent (Identifier kind _) qualIdent = (Identifier kind qualIdent)                      
setQualIdent (TypeConstructor kind _) qualIdent = (TypeConstructor kind qualIdent)
setQualIdent (StringCode str) _ = (StringCode str)                                 
setQualIdent (CharCode str) _ = (CharCode str)             
-}
                  
code2string (Keyword str) = str
code2string (Space i)= concat (replicate i " ")
code2string NewLine = "\n"
code2string (ConstructorName _ qualIdent) = name $ unqualify qualIdent
code2string (Function _ qualIdent) = name $ unqualify qualIdent
code2string (ModuleName moduleIdent) = moduleName moduleIdent
code2string (Commentary str) = str
code2string (NumberCode str) = str
code2string (Symbol str) = str
code2string (Identifier _ qualIdent) = name $ unqualify qualIdent                      
code2string (TypeConstructor _ qualIdent) = name $ unqualify qualIdent
code2string (StringCode str) = str                                 
code2string (CharCode str) = str
code2string (NotParsed str) = str
code2string _ = "" -- error / warning
 
code2qualString (ConstructorName _ qualIdent) = qualName qualIdent
code2qualString (Function _ qualIdent) = qualName qualIdent
code2qualString (Identifier _ qualIdent) = qualName qualIdent                      
code2qualString (TypeConstructor _ qualIdent) = qualName qualIdent
code2qualString x = code2string x



token2code :: Token -> Code
token2code tok@(Token cat _)
    | elem cat [IntTok,FloatTok,IntegerTok]
         = NumberCode (token2string tok)
    | elem cat [KW_case,KW_choice,KW_data,KW_do,KW_else,KW_eval,KW_external,
                KW_free,KW_if,KW_import,KW_in,KW_infix,KW_infixl,KW_infixr,
                KW_let,KW_module,KW_newtype,KW_of,KW_rigid,KW_then,KW_type,
                KW_where,Id_as,Id_ccall,Id_forall,Id_hiding,Id_interface,Id_primitive]
         =  Keyword (token2string tok)
    | elem cat [LeftParen,RightParen,Semicolon,LeftBrace,RightBrace,LeftBracket,
                RightBracket,Comma,Underscore,Backquote,
                At,Colon,DotDot,DoubleColon,Equals,Backslash,Bar,LeftArrow,RightArrow,
                Tilde]
         = Symbol (token2string tok)
    | elem cat [LineComment, NestedComment]
         = Commentary (token2string tok)
    | isTokenIdentifier tok
         = Identifier UnknownId $ qualify $ mkIdent $ token2string tok
    | cat == StringTok 
         = StringCode (token2string tok)
    | cat == CharTok
         = CharCode (token2string tok)          
    | elem cat [EOF,VSemicolon,VRightBrace] = Space 0 
    
isTokenIdentifier :: Token -> Bool
isTokenIdentifier (Token cat _) = 
  elem cat [Id_qualified,Id,QId,Sym,QSym,Sym_Dot,Sym_Minus,Sym_MinusDot]
    
-- DECL Position

getPosition :: Decl -> Position
getPosition (ImportDecl pos _ _ _ _) = pos     
getPosition (InfixDecl pos _ _ _) = pos     
getPosition (DataDecl pos _ _ _) = pos     
getPosition (NewtypeDecl pos _ _ _) = pos
getPosition (TypeDecl pos _ _ _) = pos   
getPosition (TypeSig pos _ _) = pos    
getPosition (EvalAnnot pos _ _) = pos
getPosition (FunctionDecl pos _ _) = pos    
getPosition (ExternalDecl pos _ _ _ _) = pos
getPosition (FlatExternalDecl pos _) = pos    
getPosition (PatternDecl pos _ _) = pos    
getPosition (ExtraVariables pos _) = pos
             

lessDecl :: Decl -> Decl -> Bool
lessDecl decl1 decl2 = getPosition decl1 < getPosition decl2

qsort _ []     = []
qsort less (x:xs) = qsort less [y | y <- xs, less y x] ++ [x] ++ qsort less [y | y <- xs, not $ less y x]

-- DECL TO CODE -------------------------------------------------------------------- 

exportSpec2codes :: [QualIdent] -> ExportSpec -> [Code]
exportSpec2codes qualIdents (Exporting _ exports) = concatMap (export2codes qualIdents) exports

export2codes :: [QualIdent] -> Export -> [Code]
export2codes qualIdents (Export qualIdent) 
    | elem qualIdent qualIdents = [TypeConstructor TypeUse qualIdent]
    | otherwise = [Function OtherFunctionKind qualIdent]  
export2codes _ (ExportTypeWith qualIdent idents) = 
     [TypeConstructor TypeUse qualIdent] ++ map (Function OtherFunctionKind . qualify) idents
export2codes _ (ExportTypeAll  qualIdent) = 
     [TypeConstructor TypeUse qualIdent]  
export2codes _ (ExportModule moduleIdent) = 
     [ModuleName moduleIdent]

decl2codes :: Decl -> [Code]            
decl2codes (ImportDecl _ moduleIdent xQualified xModuleIdent importSpec) = 
     [ModuleName moduleIdent] ++
     maybe [] importSpec2codes  importSpec
decl2codes (InfixDecl _ _ _ idents) =
     (map (Function InfixFunction . qualify) idents) 
decl2codes (DataDecl _ ident idents constrDecls) =
     [TypeConstructor TypeDecla (qualify ident)] ++ 
     map (Identifier UnknownId . qualify) idents ++
     concatMap constrDecl2codes constrDecls
decl2codes (NewtypeDecl xPosition xIdent yIdents xNewConstrDecl) =
     []
decl2codes (TypeDecl _ ident idents typeExpr) =
     TypeConstructor TypeDecla (qualify ident) : 
     map (Identifier UnknownId . qualify) idents ++ 
     typeExpr2codes typeExpr
decl2codes (TypeSig _ idents typeExpr) =
     map (Function TypSig . qualify) idents ++ typeExpr2codes typeExpr   
decl2codes (EvalAnnot xPosition idents xEvalAnnotation) =
     map (Function FunDecl . qualify) idents
decl2codes (FunctionDecl _ _ equations) =
     concatMap equation2codes equations  
decl2codes (ExternalDecl xPosition xCallConv xString xIdent xTypeExpr) =
     []
decl2codes (FlatExternalDecl _ idents) =
     map (Function FunDecl . qualify) idents   
decl2codes (PatternDecl xPosition constrTerm rhs) =
     constrTerm2codes constrTerm ++ rhs2codes rhs
decl2codes (ExtraVariables _ idents) =
     map (Identifier IdDecl . qualify) idents
  
equation2codes :: Equation -> [Code]
equation2codes (Equation _ lhs rhs) =
     lhs2codes lhs ++ rhs2codes rhs
     
lhs2codes :: Lhs -> [Code]
lhs2codes (FunLhs ident constrTerms) =
    (Function FunDecl $ qualify ident) : concatMap constrTerm2codes constrTerms
lhs2codes (OpLhs constrTerm1 ident constrTerm2) =
    constrTerm2codes constrTerm1 ++ [Function FunDecl $ qualify ident] ++ constrTerm2codes constrTerm2
lhs2codes (ApLhs lhs constrTerms) =
    lhs2codes lhs ++ concatMap constrTerm2codes constrTerms     

rhs2codes :: Rhs -> [Code]
rhs2codes (SimpleRhs _ expression decls) =
    expression2codes expression ++ concatMap decl2codes decls
rhs2codes (GuardedRhs condExprs decls) =
    concatMap condExpr2codes condExprs ++ concatMap decl2codes decls
    
condExpr2codes :: CondExpr -> [Code]
condExpr2codes (CondExpr _ expression1 expression2) =   
   expression2codes expression1 ++ expression2codes expression2    
    
constrTerm2codes :: ConstrTerm -> [Code]
constrTerm2codes (LiteralPattern literal) = []
constrTerm2codes (NegativePattern ident literal) = []
constrTerm2codes (VariablePattern ident) = [Identifier IdDecl (qualify ident)]
constrTerm2codes (ConstructorPattern qualIdent constrTerms) =
    (ConstructorName ConstrPattern qualIdent) : concatMap constrTerm2codes constrTerms
constrTerm2codes (InfixPattern constrTerm1 qualIdent constrTerm2) =
    constrTerm2codes constrTerm1 ++ [ConstructorName ConstrPattern qualIdent] ++ constrTerm2codes constrTerm2
constrTerm2codes (ParenPattern constrTerm) = constrTerm2codes constrTerm
constrTerm2codes (TuplePattern constrTerms) = concatMap constrTerm2codes constrTerms
constrTerm2codes (ListPattern constrTerms) = concatMap constrTerm2codes constrTerms
constrTerm2codes (AsPattern ident constrTerm) =
    (Function OtherFunctionKind $ qualify ident) : constrTerm2codes constrTerm
constrTerm2codes (LazyPattern constrTerm) = constrTerm2codes constrTerm
constrTerm2codes (FunctionPattern qualIdent constrTerms) = 
    (Function OtherFunctionKind qualIdent) : concatMap constrTerm2codes constrTerms
constrTerm2codes (InfixFuncPattern constrTerm1 qualIdent constrTerm2) =
    constrTerm2codes constrTerm1 ++ [Function InfixFunction qualIdent] ++ constrTerm2codes constrTerm2
   
expression2codes :: Expression -> [Code]
expression2codes (Literal literal) = []
expression2codes (Variable qualIdent) = 
    [Identifier IdOccur qualIdent]
expression2codes (Constructor qualIdent) = 
    [ConstructorName ConstrCall qualIdent]
expression2codes (Paren expression) = 
    expression2codes expression
expression2codes (Typed expression typeExpr) = 
    expression2codes expression ++ typeExpr2codes typeExpr
expression2codes (Tuple expressions) = 
    concatMap expression2codes expressions
expression2codes (List expressions) = 
    concatMap expression2codes expressions
expression2codes (ListCompr expression statements) = 
    expression2codes expression ++ concatMap statement2codes statements
expression2codes (EnumFrom expression) = 
    expression2codes expression
expression2codes (EnumFromThen expression1 expression2) = 
    expression2codes expression1 ++ expression2codes expression2
expression2codes (EnumFromTo expression1 expression2) = 
    expression2codes expression1 ++ expression2codes expression2
expression2codes (EnumFromThenTo expression1 expression2 expression3) = 
    expression2codes expression1 ++ 
    expression2codes expression2 ++ 
    expression2codes expression3
expression2codes (UnaryMinus ident expression) = 
    [] ++ expression2codes expression
expression2codes (Apply expression1 expression2) = 
    expression2codes expression1 ++ expression2codes expression2
expression2codes (InfixApply expression1 infixOp expression2) = 
    expression2codes expression1 ++ infixOp2codes infixOp ++ expression2codes expression2
expression2codes (LeftSection expression infixOp) = 
    expression2codes expression ++ infixOp2codes infixOp
expression2codes (RightSection infixOp expression) = 
    infixOp2codes infixOp ++ expression2codes expression
expression2codes (Lambda constrTerms expression) = 
    concatMap constrTerm2codes constrTerms ++ expression2codes expression
expression2codes (Let decls expression) = 
    concatMap decl2codes decls ++ expression2codes expression
expression2codes (Do statements expression) = 
    concatMap statement2codes statements ++ expression2codes expression
expression2codes (IfThenElse expression1 expression2 expression3) = 
    expression2codes expression1 ++ expression2codes expression2 ++ expression2codes expression3
expression2codes (Case expression alts) = 
    expression2codes expression ++ concatMap alt2codes alts
    
infixOp2codes :: InfixOp -> [Code]
infixOp2codes (InfixOp qualIdent) = [Function InfixFunction qualIdent]
infixOp2codes (InfixConstr qualIdent) = [ConstructorName OtherConstrKind qualIdent]


statement2codes :: Statement -> [Code] 
statement2codes (StmtExpr expression) =
    expression2codes expression
statement2codes (StmtDecl decls) =
    concatMap decl2codes decls
statement2codes (StmtBind constrTerm expression) =
     constrTerm2codes constrTerm ++ expression2codes expression


alt2codes :: Alt -> [Code]
alt2codes (Alt _ constrTerm rhs) =
    constrTerm2codes constrTerm ++ rhs2codes rhs
         
constrDecl2codes :: ConstrDecl -> [Code]
constrDecl2codes (ConstrDecl _ idents ident typeExprs) =
    (ConstructorName ConstrDecla $ qualify ident) : concatMap typeExpr2codes typeExprs
constrDecl2codes (ConOpDecl _ idents typeExpr1 ident typeExpr2) =   
    typeExpr2codes typeExpr1 ++ [ConstructorName ConstrDecla $ qualify ident] ++ typeExpr2codes typeExpr2

         
importSpec2codes :: ImportSpec -> [Code]
importSpec2codes (Importing _ imports) = concatMap import2codes imports
importSpec2codes (Hiding _ imports) = concatMap import2codes imports

import2codes :: Import -> [Code]
import2codes (Import ident) =
     [Function OtherFunctionKind $ qualify ident]  
import2codes (ImportTypeWith ident idents) = 
     [ConstructorName OtherConstrKind $ qualify ident] ++ map (Function OtherFunctionKind . qualify) idents
import2codes (ImportTypeAll  ident) = 
     [ConstructorName OtherConstrKind $ qualify ident]  
     
typeExpr2codes :: TypeExpr -> [Code]     
typeExpr2codes (ConstructorType qualIdent typeExprs) = 
    (TypeConstructor TypeUse qualIdent) : concatMap typeExpr2codes typeExprs
typeExpr2codes (VariableType ident) = 
    [Identifier IdOccur (qualify ident)]
typeExpr2codes (TupleType typeExprs) = 
    concatMap typeExpr2codes typeExprs
typeExpr2codes (ListType typeExpr) = 
    typeExpr2codes typeExpr
typeExpr2codes (ArrowType typeExpr1 typeExpr2) = 
    typeExpr2codes typeExpr1 ++ typeExpr2codes typeExpr2

-- TOKEN TO STRING ------------------------------------------------------------

token2string (Token Id a) = attributes2string a
token2string (Token QId a) = attributes2string a
token2string (Token Sym a) = attributes2string a
token2string (Token QSym a) = attributes2string a
token2string (Token IntTok a) = attributes2string a
token2string (Token FloatTok a) = attributes2string a
token2string (Token CharTok a) = attributes2string a
token2string (Token IntegerTok a) = attributes2string a
token2string (Token StringTok a) = attributes2string a
token2string (Token LeftParen _) = "("
token2string (Token RightParen _) = ")"
token2string (Token Semicolon _) = ";"
token2string (Token LeftBrace _) = "{"
token2string (Token RightBrace _) = "}"
token2string (Token LeftBracket _) = "["
token2string (Token RightBracket _) = "]"
token2string (Token Comma _) = ","
token2string (Token Underscore _) = "_"
token2string (Token Backquote _) = "`"
token2string (Token VSemicolon _) = ""
token2string (Token VRightBrace _) = ""
token2string (Token At _) = "@"
token2string (Token Colon _) = ":"
token2string (Token DotDot _) = ".."
token2string (Token DoubleColon _) = "::"
token2string (Token Equals _) = "="
token2string (Token Backslash _) = "\\"
token2string (Token Bar _) = "|"
token2string (Token LeftArrow _) = "<-"
token2string (Token RightArrow _) = "->"
token2string (Token Tilde _) = "~"
token2string (Token Sym_Dot _) = "."
token2string (Token Sym_Minus _) = "-"
token2string (Token Sym_MinusDot _) = "-."
token2string (Token KW_case _) = "case"
token2string (Token KW_choice _) = "choice"
token2string (Token KW_data _) = "data"
token2string (Token KW_do _) = "do"
token2string (Token KW_else _) = "else"
token2string (Token KW_eval _) = "eval"
token2string (Token KW_external _) = "external"
token2string (Token KW_free _) = "free"
token2string (Token KW_if _) = "if"
token2string (Token KW_import _) = "import"
token2string (Token KW_in _) = "in"
token2string (Token KW_infix _) = "infix"
token2string (Token KW_infixl _) = "infixl"
token2string (Token KW_infixr _) = "infixr"
token2string (Token KW_let _) = "let"
token2string (Token KW_module _) = "module"
token2string (Token KW_newtype _) = "newtype"
token2string (Token KW_of _) = "of"
token2string (Token KW_rigid _) = "rigid"
token2string (Token KW_then _) = "then"
token2string (Token KW_type _) = "type"
token2string (Token KW_where _) = "where"
token2string (Token Id_as _) = "as"
token2string (Token Id_ccall _) = "ccall"
token2string (Token Id_forall _) = "forall"
token2string (Token Id_hiding _) = "hiding"
token2string (Token Id_interface _) = "interface"
token2string (Token Id_primitive _) = "primitive"
token2string (Token Id_qualified _) = "qualified"
token2string (Token EOF _) = ""
token2string (Token LineComment (StringAttributes sval _)) = sval
token2string (Token NestedComment (StringAttributes sval _)) = sval

attributes2string NoAttributes = ""
attributes2string (CharAttributes cval _) = showCh cval 
attributes2string (IntAttributes ival _) = show ival
attributes2string (FloatAttributes fval _) = show fval
attributes2string (IntegerAttributes intval _) = show intval
attributes2string (StringAttributes sval _) = showSt sval 
attributes2string (IdentAttributes mIdent ident) =concat (intersperse "." (mIdent ++ [ident])) 

basename = reverse .  takeWhile (/='/')    . reverse

showCh c    
   | c == '\\' = "'\\\\'"
   | elem c ('\127' : ['\001' .. '\031']) = show c
   | otherwise = toString c
  where
    toString c = "'" ++ c : "'"

showSt = addQuotes . concatMap toGoodChar 
   where
      addQuotes x = "\"" ++ x ++ "\""

toGoodChar c     
   | c == '\\' = "\\\\"
   | elem c ('\127' : ['\001' .. '\031']) = justShow c
   | c == '"' = "\\\""
   | otherwise = c : "" 
 where
     justShow = reverse . tail . reverse . tail . show  

