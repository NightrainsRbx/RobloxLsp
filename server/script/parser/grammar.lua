local re = require 'parser.relabel'
local m = require 'lpeglabel'
local ast = require 'parser.ast'

local scriptBuf = ''
local compiled = {}
<<<<<<< HEAD
local parser
=======
>>>>>>> origin/master
local defs = ast.defs

-- goto 可以作为名字，合法性之后处理
local RESERVED = {
    ['and']      = true,
    ['break']    = true,
    ['do']       = true,
    ['else']     = true,
    ['elseif']   = true,
    ['end']      = true,
    ['false']    = true,
    ['for']      = true,
    ['function'] = true,
    ['if']       = true,
    ['in']       = true,
    ['local']    = true,
    ['nil']      = true,
    ['not']      = true,
    ['or']       = true,
    ['repeat']   = true,
    ['return']   = true,
    ['then']     = true,
    ['true']     = true,
    ['until']    = true,
    ['while']    = true,
}

defs.nl = (m.P'\r\n' + m.S'\r\n')
defs.s  = m.S' \t'
defs.S  = - defs.s
defs.ea = '\a'
defs.eb = '\b'
defs.ef = '\f'
defs.en = '\n'
defs.er = '\r'
defs.et = '\t'
defs.ev = '\v'
defs['nil'] = m.Cp() / function () return nil end
defs['false'] = m.Cp() / function () return false end
<<<<<<< HEAD
=======
defs['true'] = m.Cp() / function () return true end
>>>>>>> origin/master
defs.NotReserved = function (_, _, str)
    if RESERVED[str] then
        return false
    end
    return true
end
defs.Reserved = function (_, _, str)
    if RESERVED[str] then
        return true
    end
    return false
end
defs.None = function () end
defs.np = m.Cp() / function (n) return n+1 end
<<<<<<< HEAD
=======
defs.NoNil = function (o)
    if o == nil then
        return
    end
    return o
end
>>>>>>> origin/master

m.setmaxstack(1000)

local eof = re.compile '!. / %{SYNTAX_ERROR}'

local function grammar(tag)
    return function (script)
        scriptBuf = script .. '\r\n' .. scriptBuf
        compiled[tag] = re.compile(scriptBuf, defs) * eof
    end
end

local function errorpos(pos, err)
    return {
        type = 'UNKNOWN',
        start = pos or 0,
        finish = pos or 0,
        err = err,
    }
end

grammar 'Comment' [[
<<<<<<< HEAD
Comment         <-  LongComment / '--' ShortComment
LongComment     <-  ('--[' {} {:eq: '='* :} {} '['
                    {(!CommentClose .)*}
                    (CommentClose {} / {} {}))
                ->  LongComment
                /   (
                    {} '/*' {}
                    (!'*/' .)*
                    {} '*/' {}
                    )
                ->  CLongComment
CommentClose    <-  ']' =eq ']'
ShortComment    <-  (!%nl .)*
=======
Comment         <-  LongComment
                /   '--' ShortComment
LongComment     <-  ({} '--[' {} {:eq: '='* :} {} '[' %nl?
                    {(!CommentClose .)*}
                    ((CommentClose / %nil) {}))
                ->  LongComment
CommentClose    <-  {']' =eq ']'}
ShortComment    <-  ({} {(!%nl .)*} {})
                ->  ShortComment
>>>>>>> origin/master
]]

grammar 'Sp' [[
Sp  <-  (Comment / %nl / %s)*
Sps <-  (Comment / %nl / %s)+
]]

grammar 'Common' [[
Word        <-  [a-zA-Z0-9_]
Cut         <-  !Word
X16         <-  [a-fA-F0-9]
Rest        <-  (!%nl .)*

AND         <-  Sp {'and'}    Cut
BREAK       <-  Sp 'break'    Cut
<<<<<<< HEAD
CONTINUE    <-  Sp 'continue' Cut
DO          <-  Sp 'do'       Cut
            /   Sp ({} 'then' Cut {}) -> ErrDo
ELSE        <-  Sp 'else'     Cut
ELSEIF      <-  Sp 'elseif'   Cut
END         <-  Sp 'end'      Cut
FALSE       <-  Sp 'false'    Cut
FOR         <-  Sp 'for'      Cut
FUNCTION    <-  Sp 'function' Cut
GOTO        <-  Sp 'goto'     Cut
IF          <-  Sp 'if'       Cut
IN          <-  Sp 'in'       Cut
=======
FALSE       <-  Sp 'false'    Cut
>>>>>>> origin/master
LOCAL       <-  Sp 'local'    Cut
NIL         <-  Sp 'nil'      Cut
NOT         <-  Sp 'not'      Cut
OR          <-  Sp {'or'}     Cut
<<<<<<< HEAD
REPEAT      <-  Sp 'repeat'   Cut
RETURN      <-  Sp 'return'   Cut
THEN        <-  Sp 'then'     Cut
            /   Sp ({} 'do' Cut {}) -> ErrThen
TRUE        <-  Sp 'true'     Cut
UNTIL       <-  Sp 'until'    Cut
WHILE       <-  Sp 'while'    Cut
=======
RETURN      <-  Sp 'return'   Cut
TRUE        <-  Sp 'true'     Cut
CONTINUE    <-  Sp 'continue' Cut
EXPORT      <-  Sp 'export'   Cut
TYPE        <-  Sp 'type'     Cut

DO          <-  Sp {} 'do'       {} Cut
            /   Sp({} 'then'     {} Cut) -> ErrDo
IF          <-  Sp {} 'if'       {} Cut
ELSE        <-  Sp {} 'else'     {} Cut
ELSEIF      <-  Sp {} 'elseif'   {} Cut
END         <-  Sp {} 'end'      {} Cut
FOR         <-  Sp {} 'for'      {} Cut
FUNCTION    <-  Sp {} 'function' {} Cut
IN          <-  Sp {} 'in'       {} Cut
REPEAT      <-  Sp {} 'repeat'   {} Cut
THEN        <-  Sp {} 'then'     {} Cut
            /   Sp({} 'do'       {} Cut) -> ErrThen
UNTIL       <-  Sp {} 'until'    {} Cut
WHILE       <-  Sp {} 'while'    {} Cut

>>>>>>> origin/master

Esc         <-  '\' -> ''
                EChar
EChar       <-  'a' -> ea
            /   'b' -> eb
            /   'f' -> ef
            /   'n' -> en
            /   'r' -> er
            /   't' -> et
            /   'v' -> ev
            /   '\'
            /   '"'
            /   "'"
            /   %nl
            /   ('z' (%nl / %s)*)       -> ''
            /   ({} 'x' {X16 X16})      -> Char16
            /   ([0-9] [0-9]? [0-9]?)   -> Char10
            /   ('u{' {} {Word*} '}')   -> CharUtf8
            -- 错误处理
            /   'x' {}                  -> MissEscX
            /   'u' !'{' {}             -> MissTL
            /   'u{' Word* !'}' {}      -> MissTR
            /   {}                      -> ErrEsc

<<<<<<< HEAD
BOR         <-  Sp {'|'}
BXOR        <-  Sp {'~'} !'='
BAND        <-  Sp {'&'}
Bshift      <-  Sp {BshiftList}
BshiftList  <-  '<<'
            /   '>>'
=======
>>>>>>> origin/master
Concat      <-  Sp {'..'}
Adds        <-  Sp {AddsList}
AddsList    <-  '+'
            /   '-'
Muls        <-  Sp {MulsList}
MulsList    <-  '*'
            /   '//'
            /   '/'
            /   '%'
Unary       <-  Sp {} {UnaryList}
UnaryList   <-  NOT
            /   '#'
            /   '-'
<<<<<<< HEAD
            /   '~' !'='
POWER       <-  Sp {'^'}

BinaryOp    <-  Sp {} {'or'} Cut
=======
POWER       <-  Sp {'^'}

BinaryOp    <-( Sp {} {'or'} Cut
>>>>>>> origin/master
            /   Sp {} {'and'} Cut
            /   Sp {} {'<=' / '>=' / '<'!'<' / '>'!'>' / '~=' / '=='}
            /   Sp {} ({} '=' {}) -> ErrEQ
            /   Sp {} ({} '!=' {}) -> ErrUEQ
<<<<<<< HEAD
            /   Sp {} {'|'}
            /   Sp {} {'~'}
            /   Sp {} {'&'}
            /   Sp {} {'<<' / '>>'}
            /   Sp {} {'..'} !'.'
            /   Sp {} {'+' / '-'}
            /   Sp {} {'*' / '//' / '/' / '%'}
            /   Sp {} {'^'}
UnaryOp     <-  Sp {} {'not' Cut / '#' / '~' !'=' / '-' !'-'}
=======
            /   Sp {} {'..'} !'.'
            /   Sp {} {'+' / '-'}
            /   Sp {} {'*' / '/' / '%'}
            /   Sp {} {'^'}
            )-> BinaryOp
UnaryOp     <-( Sp {} {'not' Cut / '#' / '-' !'-'}
            )-> UnaryOp
>>>>>>> origin/master

PL          <-  Sp '('
PR          <-  Sp ')'
BL          <-  Sp '[' !'[' !'='
BR          <-  Sp ']'
TL          <-  Sp '{'
TR          <-  Sp '}'
<<<<<<< HEAD
COMMA       <-  Sp ','
SEMICOLON   <-  Sp ';'
BAR         <-  Sp '|'
DOTS        <-  Sp ({} '...') -> DOTS
DOT         <-  Sp ({} '.' !'.') -> DOT
COLON       <-  Sp ({} ':' !':') -> COLON
LABEL       <-  Sp '::'
COMPASSIGN  <-  Sp {} {('+=' / '-=' / '*=' / '/=' / '^=' / '..=' / '%=')} {} !'='
ASSIGN      <-  Sp '=' !'='
AssignOrEQ  <-  Sp ({} '==' {}) -> ErrAssign
            /   Sp '='

Nothing     <-  {} -> Nothing

DirtyBR     <-  BR {}  / {} -> MissBR
DirtyTR     <-  TR {}  / {} -> MissTR
DirtyPR     <-  PR {}  / {} -> DirtyPR
DirtyLabel  <-  LABEL  / {} -> MissLabel
NeedPR      <-  PR     / {} -> MissPR
=======
AL          <-  Sp '<'
AR          <-  Sp '>'
COMMA       <-  Sp ({} ',')
            ->  COMMA
SEMICOLON   <-  Sp ({} ';')
            ->  SEMICOLON
DOTS        <-  Sp ({} '...')
            ->  DOTS
DOT         <-  Sp ({} '.' !'.')
            ->  DOT
COLON       <-  Sp ({} ':' !':')
            ->  COLON
LABEL       <-  Sp '::'
ARROW       <-  Sp '->'
ASSIGN      <-  Sp '=' !'='
COMPASSIGN  <-  Sp ({} {('+' / '-' / '*' / '/' / '^' / '..' / '%')} '=' !'=' {})
            ->  CompOp
AssignOrEQ  <-  Sp ({} '==' {})
            ->  ErrAssign
            /   ASSIGN

DirtyBR     <-  BR     / {} -> MissBR
DirtyTR     <-  TR     / {} -> MissTR
DirtyPR     <-  PR     / {} -> MissPR
DirtyAR     <-  AR     / {} -> MissAR
>>>>>>> origin/master
NeedEnd     <-  END    / {} -> MissEnd
NeedDo      <-  DO     / {} -> MissDo
NeedAssign  <-  ASSIGN / {} -> MissAssign
NeedComma   <-  COMMA  / {} -> MissComma
NeedIn      <-  IN     / {} -> MissIn
NeedUntil   <-  UNTIL  / {} -> MissUntil
<<<<<<< HEAD
=======
NeedThen    <-  THEN   / {} -> MissThen
>>>>>>> origin/master
]]

grammar 'Nil' [[
Nil         <-  Sp ({} -> Nil) NIL
]]

grammar 'Boolean' [[
Boolean     <-  Sp ({} -> True)  TRUE
            /   Sp ({} -> False) FALSE
]]

grammar 'String' [[
String      <-  Sp ({} StringDef {})
            ->  String
StringDef   <-  {'"'}
                {~(Esc / !%nl !'"' .)*~} -> 1
                ('"' / {} -> MissQuote1)
            /   {"'"}
                {~(Esc / !%nl !"'" .)*~} -> 1
                ("'" / {} -> MissQuote2)
            /   ('[' {} {:eq: '='* :} {} '[' %nl?
                {(!StringClose .)*} -> 1
                (StringClose / {}))
            ->  LongString
StringClose <-  ']' =eq ']'
]]

grammar 'Number' [[
Number      <-  Sp ({} {NumberDef} {}) -> Number
<<<<<<< HEAD
                NumberSuffix?
                ErrNumber?
NumberDef   <-  Number16 / Number2 / Number10
NumberSuffix<-  ({} {[uU]? [lL] [lL]})      -> FFINumber
            /   ({} {[iI]})                 -> ImaginaryNumber
=======
                ErrNumber?
NumberDef   <-  Number16 / Number2 / Number10
>>>>>>> origin/master
ErrNumber   <-  ({} {([0-9a-zA-Z] / '.')+}) -> UnknownSymbol

Number10    <-  Float10 Float10Exp?
            /   Integer10 Float10? Float10Exp?
Integer10   <-  Num+ ('.' Num*)?
Float10     <-  '.' Num+
Float10Exp  <-  [eE] [+-]? NumWithSep+
            /   ({} [eE] [+-]? {}) -> MissExponent

Number16    <-  '0' [xX] Integer16
Integer16   <-  HexWithSep+
            /   ({} {Word*}) -> MustX16

Number2     <-  '0' [bB] Integer2
Integer2    <-  BinWithSep+
            /   ({} {Word*}) -> MustX2

Num         <-  [0-9] [0-9_]*
NumWithSep  <-  [0-9_]+
HexWithSep  <-  [0-9A-Fa-f_]+
BinWithSep  <-  [01_]+
]]

grammar 'Name' [[
Name        <-  Sp ({} NameBody {})
            ->  Name
<<<<<<< HEAD
NameBody    <-  {[a-zA-Z_] [a-zA-Z0-9_]*}
FreeName    <-  Sp ({} {NameBody=>NotReserved} {})
            ->  Name
=======
NameStr     <-  [a-zA-Z_] [a-zA-Z0-9_]*
NameBody    <-  {NameStr}
FreeName    <-  Sp ({} {NameBody=>NotReserved} {})
            ->  Name
KeyWord     <-  Sp NameBody=>Reserved
>>>>>>> origin/master
MustName    <-  Name / DirtyName
DirtyName   <-  {} -> DirtyName
]]

grammar 'Exp' [[
<<<<<<< HEAD
Exp         <-  (UnUnit (BinaryOp (UnUnit / {} -> DirtyExp))*)
            ->  Exp
UnUnit      <-  Assert
            /   UnaryOp+ (Assert / {} -> DirtyExp)
Assert      <-  (ExpUnit (LABEL Type)?)
=======
Exp         <-  (UnUnit BinUnit*)
            ->  Binary
BinUnit     <-  (BinaryOp UnUnit?)
            ->  SubBinary
UnUnit      <-  TypeAssert
            /   (UnaryOp+ (TypeAssert / MissExp))
            ->  Unary
TypeAssert  <-  (ExpUnit (LABEL Type)?)
>>>>>>> origin/master
            ->  TypeAssert
ExpUnit     <-  Nil
            /   Boolean
            /   String
            /   Number
<<<<<<< HEAD
            /   DOTS -> DotsAsExp
            /   Table
            /   Function
            /   Simple

Simple      <-  (Prefix (Sp Suffix)*)
            ->  Simple
Prefix      <-  Sp ({} PL DirtyExp DirtyPR)
            ->  Prefix
            /   FreeName
Index       <-  ({} BL DirtyExp DirtyBR) -> Index
Suffix      <-  DOT   Name / DOT   {} -> MissField
            /   Method (!(Sp CallStart) {} -> MissPL)?
            /   ({} Table {}) -> Call
            /   ({} String {}) -> Call
            /   Index
            /   ({} PL CallArgList DirtyPR) -> Call
Method      <-  COLON Name / COLON {} -> MissMethod
=======
            /   Dots
            /   Table
            /   ExpFunction
            /   Simple

Simple      <-  {| Prefix (Sp Suffix)* |}
            ->  Simple
Prefix      <-  Sp ({} PL DirtyExp DirtyPR {})
            ->  Paren
            /   Single
Single      <-  !FUNCTION FreeName
            ->  Single
Suffix      <-  SuffixWithoutCall
            /   ({} PL SuffixCall DirtyPR {})
            ->  Call
SuffixCall  <-  Sp ({} {| (COMMA / Exp->NoNil)+ |} {})
            ->  PackExpList
            /   %nil
SuffixWithoutCall
            <-  (DOT (Name / MissField))
            ->  GetField
            /   ({} BL DirtyExp DirtyBR {})
            ->  GetIndex
            /   (COLON (Name / MissMethod) NeedCall)
            ->  GetMethod
            /   ({} {| Table |} {})
            ->  Call
            /   ({} {| String |} {})
            ->  Call
NeedCall    <-  (!(Sp CallStart) {} -> MissPL)?
MissField   <-  {} -> MissField
MissMethod  <-  {} -> MissMethod
>>>>>>> origin/master
CallStart   <-  PL
            /   TL
            /   '"'
            /   "'"
            /   '[' '='* '['

<<<<<<< HEAD
DirtyExp    <-  Exp
            /   {} -> DirtyExp
MaybeExp    <-  Exp / MissExp
MissExp     <-  {} -> MissExp
ExpList     <-  Sp (MaybeExp (COMMA (MaybeExp))*)
            ->  List
MustExpList <-  Sp (Exp      (COMMA (MaybeExp))*)
            ->  List
CallArgList <-  Sp ({} (COMMA {} / Exp)+ {})
            ->  CallArgList
            /   %nil
NameList    <-  (MustName ParamType? (COMMA MustName ParamType?)*)
            ->  List

ArgList     <-  ((DOTS -> DotsAsArg ParamType?) / (Name ParamType?) / Sp {} COMMA)*
            ->  ArgList

Table       <-  Sp ({} TL TableFields? DirtyTR)
            ->  Table
TableFields <-  (Emmy / TableSep {} / TableField)+
TableSep    <-  COMMA / SEMICOLON
TableField  <-  NewIndex / NewField / Exp
NewIndex    <-  Sp (Index NeedAssign DirtyExp)
            ->  NewIndex
NewField    <-  (MustName ASSIGN DirtyExp)
            ->  NewField

Function    <-  Sp ({} FunctionBody {})
            ->  Function
FuncArg     <-  PL {} ArgList {} NeedPR
            /   {} {} -> MissPL Nothing {}
FunctionBody<-  FUNCTION BlockStart FuncArg ReturnType?
                    (Emmy / !END Action)*
                    BlockEnd
                NeedEnd

BlockStart  <-  {} -> BlockStart
BlockEnd    <-  {} -> BlockEnd

-- 纯占位，修改了 `relabel.lua` 使重复定义不抛错
Action      <-  !END .
Set         <-  END
Emmy        <-  '---@'

-- Type Grammars
TypeOp      <-  Sp {} {'|'}
            /   Sp {} {'&'}

Optional    <-  Sp ('?')*

Type        <-  Sp (UnTypeUnit (TypeOp (UnTypeUnit / {} -> DirtyExp))*)
            ->  Exp
UnTypeUnit  <-  TypeUnit
            /   UnaryOp+ (TypeUnit / {} -> DirtyExp)
=======
DirtyExp    <-  !THEN !DO !END Exp
            /   {} -> DirtyExp
MaybeExp    <-  Exp / MissExp
MissExp     <-  {} -> MissExp
ExpList     <-  Sp {| MaybeExp (Sp ',' MaybeExp)* |}

Dots        <-  DOTS
            ->  VarArgs

Table       <-  Sp ({} TL {| TableField* |} DirtyTR {})
            ->  Table
TableField  <-  COMMA
            /   SEMICOLON
            /   NewIndex
            /   NewField
            /   Exp->NoNil
Index       <-  BL DirtyExp DirtyBR
NewIndex    <-  Sp ({} Index NeedAssign DirtyExp {})
            ->  NewIndex
NewField    <-  Sp ({} MustName ASSIGN DirtyExp {})
            ->  NewField

ExpFunction <-  Function
            ->  ExpFunction
Function    <-  FunctionBody
            ->  Function
FunctionBody
            <-  FUNCTION FuncName FuncArgs {} ReturnTypeAnn
                    {| (!END Action)* |}
                NeedEnd
            /   FUNCTION FuncName FuncArgsMiss {} ReturnTypeAnn
                    {| %nil |}
                NeedEnd
FuncName    <-  !END {| Single (Sp SuffixWithoutCall)* |}
            ->  Simple
            /   %nil

FuncArgs    <-  Sp ({} PL {| FuncArg+ |} DirtyPR {})
            ->  FuncArgs
            /   PL DirtyPR %nil
FuncArgsMiss<-  {} -> MissPL DirtyPR %nil
FuncArg     <-  DOTS TypeAnn?
            /   Name TypeAnn?
            /   COMMA

-- 纯占位，修改了 `relabel.lua` 使重复定义不抛错
Action      <-  !END .

-- Type Grammars
TypeOp      <-  (Sp {} {'|'}
            /   Sp {} {'&'})
            ->  BinaryOp

Optional    <-  Sp ({} {'?'})
            ->  Optional

Type        <-  (TypeUnit (SubType)*)
            ->  Type
SubType     <-  (TypeOp TypeUnit?)
            ->  SubType

>>>>>>> origin/master
TypeUnit    <-  ModuleType
            /   Typeof
            /   NameType
            /   FuncType
            /   TableType
<<<<<<< HEAD
            /   VariadicType
            /   TypeSimple

TypeSimple  <-  Sp ({} PL Type DirtyPR Optional)
            ->  Prefix
            /   FreeName

Typeof      <-  Sp ({} 'typeof' PL DirtyExp NeedPR {} Optional)
            ->  Typeof

Generics1   <-  Sp ({} '<' Sp (Name / Sp COMMA {})+ Sp '>' {})
            ->  Generics
Generics2   <-  Sp ({} '<' Sp (Type / Sp COMMA {})+ Sp '>' {})
            ->  Generics

TypeIdTag   <-  ({} Name Sp COLON {})
            ->  TypeIdTag
FuncTypeList
            <-  ({} PL ((TypeIdTag? Sp Type) / Sp COMMA {})* NeedPR {} Optional)
            ->  TypeList
TypeList    <-  ({} PL (Type / Sp COMMA {})* NeedPR {} Optional)
            ->  TypeList

NameType    <-  Sp ({} NameBody {} Generics2? Optional)
            ->  NameType
ModuleType  <-  Sp ({} NameBody DOT NameType {})
            ->  ModuleType
FuncType    <-  Sp ({} FuncTypeList Sp '->' (TypeList / Type) {})
=======
            /   TypeSimple

TypeSimple  <-  ({| TypePrefix |} Optional?)
            ->  TypeSimple
TypePrefix  <-  Sp ({} PL Type !COMMA DirtyPR {})
            ->  Paren
            /   Single

DirtyType   <-  Type
            /   {} -> DirtyType

Typeof      <-  Sp ({} 'typeof' Sp {} PL Exp DirtyPR {} Optional?)
            ->  Typeof

Generics1   <-  Sp ({} AL Sp {| (Name / COMMA)+ |} Sp DirtyAR {})
            ->  Generics
            /   %nil
Generics2   <-  Sp ({} AL Sp {| (Type / COMMA)+ |} Sp DirtyAR {})
            ->  Generics
            /   %nil
TypeList    <-  Sp ({} PL {| (Type / VariadicType / COMMA)* |} DirtyPR {})
            ->  TypeList
NamedType   <-  Sp (Name COLON Type) 
            ->  NamedType
ArgTypeList <-  Sp ({} PL {| (NamedType / Type / VariadicType / COMMA)* |} DirtyPR {})
            ->  TypeList
ModuleType  <-  Sp ({} (Name -> Single) DOT (NameType / %nil) {})
            ->  ModuleType
NameType    <-  Sp ({} NameBody Generics2 {} Optional?)
            ->  NameType
FuncType    <-  Sp ({} ArgTypeList ARROW (Type / VariadicType / TypeList Optional?) {})
>>>>>>> origin/master
            ->  FuncType
VariadicType    
            <-  Sp ({} DOTS Type {})
            ->  VariadicType

<<<<<<< HEAD
FieldType   <-  Sp ({} Name COLON Type {}) ->  FieldType1
            /   Sp ({} BL Type DirtyBR COLON Type {}) ->  FieldType2
            /   Sp ({} Type {}) ->  FieldType3
FieldList   <-  (FieldType / Sp COMMA {})*
            ->  FieldTypeList
TableType   <-  Sp ({} TL FieldList DirtyTR Optional)
            ->  TableType

VarType     <-  (COLON Type)
            ->  VarType
ParamType   <-  (COLON Type)
            ->  ParamType
ReturnType  <-  (COLON (TypeList / Type))
            ->  ReturnType
=======
FieldType   <-  Sp ({} Name COLON Type {}) 
            ->  FieldType
            /   Sp ({} BL Type DirtyBR COLON Type {}) 
            ->  IndexType
            /   Type
FieldList   <-  {| (FieldType / COMMA / Sp SEMICOLON)* |}
            ->  FieldTypeList
TableType   <-  Sp ({} TL FieldList DirtyTR {} Optional?)
            ->  TableType

TypeAnn     <-  (COLON {} Type {})
            ->  TypeAnn
ReturnTypeAnn
            <-  (COLON {} (Type / VariadicType / TypeList) {})
            ->  TypeAnn
            /   %nil
>>>>>>> origin/master
]]

grammar 'Action' [[
Action      <-  Sp (CrtAction / UnkAction)
CrtAction   <-  Semicolon
<<<<<<< HEAD
            /   TypeDef
            /   Do
            /   Break
            /   Continue
            /   Return
            /   Label
            /   GoTo
=======
            /   Do
            /   Break
            /   Return
>>>>>>> origin/master
            /   If
            /   For
            /   While
            /   Repeat
            /   NamedFunction
            /   LocalFunction
            /   Local
<<<<<<< HEAD
            /   Set
=======
            /   TypeAlias
            /   Set
            /   Continue
>>>>>>> origin/master
            /   Call
            /   ExpInAction
UnkAction   <-  ({} {Word+})
            ->  UnknownAction
<<<<<<< HEAD
            /   ({} '//' {} (LongComment / ShortComment))
            ->  CCommentPrefix
=======
>>>>>>> origin/master
            /   ({} {. (!Sps !CrtAction .)*})
            ->  UnknownAction
ExpInAction <-  Sp ({} Exp {})
            ->  ExpInAction

<<<<<<< HEAD
Semicolon   <-  SEMICOLON
            ->  Skip
SimpleList  <-  (Simple (COMMA Simple)*)
            ->  List

TypeDef     <-  Sp ({} ('export' Sps)? 'type' Cut Name Generics1? AssignOrEQ Type {})
            ->  TypeDef

Do          <-  Sp ({} 'do' Cut DoBody NeedEnd {})
            ->  Do
DoBody      <-  (Emmy / !END Action)*
            ->  DoBody

Break       <-  BREAK ({} Semicolon* AfterBreak?)
            ->  Break
AfterBreak  <-  Sp !END !UNTIL !ELSEIF !ELSE Action
BreakStart  <-  {} -> BreakStart
BreakEnd    <-  {} -> BreakEnd

Continue    <-  CONTINUE ({} (Sp ';'? !%p) Semicolon* AfterContinue?)
            ->  Continue
AfterContinue  <-  Sp !END !UNTIL !ELSEIF !ELSE Action
ContinueStart  <-  {} -> ContinueStart
ContinueEnd    <-  {} -> ContinueEnd

Return      <-  (ReturnBody Semicolon* AfterReturn?)
            ->  AfterReturn
ReturnBody  <-  Sp ({} RETURN MustExpList? {})
            ->  Return
AfterReturn <-  Sp !END !UNTIL !ELSEIF !ELSE Action

Label       <-  Sp ({} LABEL MustName DirtyLabel {}) -> Label

GoTo        <-  Sp ({} GOTO MustName {}) -> GoTo

If          <-  Sp ({} IfBody {})
            ->  If
IfHead      <-  (IfPart     -> IfBlock)
            /   ({} ElseIfPart -> ElseIfBlock)
            ->  MissIf
            /   ({} ElsePart   -> ElseBlock)
            ->  MissIf
IfBody      <-  IfHead
                (ElseIfPart -> ElseIfBlock)*
                (ElsePart   -> ElseBlock)?
                NeedEnd
IfPart      <-  IF DirtyExp THEN
                    {} (Emmy / !ELSEIF !ELSE !END Action)* {}
            /   IF DirtyExp {}->MissThen
                    {}        {}
ElseIfPart  <-  ELSEIF DirtyExp THEN
                    {} (Emmy / !ELSE !ELSEIF !END Action)* {}
            /   ELSEIF DirtyExp {}->MissThen
                    {}         {}
ElsePart    <-  ELSE
                    {} (Emmy / !END Action)* {}

For         <-  Loop / In
            /   FOR

Loop        <-  Sp ({} LoopBody {})
            ->  Loop
LoopBody    <-  FOR LoopStart LoopFinish LoopStep NeedDo
                    BreakStart
                    (Emmy / !END Action)*
                    BreakEnd
                NeedEnd
LoopStart   <-  MustName AssignOrEQ DirtyExp
LoopFinish  <-  NeedComma DirtyExp
LoopStep    <-  COMMA DirtyExp
            /   NeedComma Exp
            /   Nothing

In          <-  Sp ({} InBody {})
            ->  In
InBody      <-  FOR InNameList NeedIn ExpList NeedDo
                    BreakStart
                    (Emmy / !END Action)*
                    BreakEnd
                NeedEnd
InNameList  <-  &IN DirtyName
            /   NameList

While       <-  Sp ({} WhileBody {})
            ->  While
WhileBody   <-  WHILE DirtyExp NeedDo
                    BreakStart
                    (Emmy / !END Action)*
                    BreakEnd
                NeedEnd

Repeat      <-  Sp ({} RepeatBody {})
            ->  Repeat
RepeatBody  <-  REPEAT
                    BreakStart
                    (Emmy / !UNTIL Action)*
                    BreakEnd
                NeedUntil DirtyExp

LocalTag    <-  (Sp '<' Sp MustName Sp LocalTagEnd)*
            ->  LocalTag
LocalTagEnd <-  '>' / {} -> MissGT
Local       <-  (LOCAL LocalNameList (AssignOrEQ ExpList)?)
            ->  Local
Set         <-  (SimpleList AssignOrEQ ExpList?)    ->  Set
            /   (SimpleList COMPASSIGN ExpList?)    ->  CompSet

LocalNameList
            <-  (LocalName VarType? (COMMA LocalName VarType?)*)
            ->  List
LocalName   <-  (MustName LocalTag)
            ->  LocalName

=======
Semicolon   <-  Sp ';'
SimpleList  <-  {| Simple (Sp ',' Simple)* |}

TypeAliasName
            <-  (Sp ({} ({NameStr '.' NameStr} / NameBody) {}))
            ->  Name

TypeAlias   <-  Sp ({} (EXPORT %true / %false) TYPE TypeAliasName Generics1 AssignOrEQ DirtyType {})
            ->  TypeAlias

Do          <-  Sp ({} 
                'do' Cut
                    {| (!END Action)* |}
                NeedEnd)
            ->  Do

Break       <-  Sp ({} BREAK {})
            ->  Break

Continue    <-  Sp ({} CONTINUE {} (Sp ';'? !%p))
            ->  Continue

Return      <-  Sp ({} RETURN ReturnExpList {})
            ->  Return
ReturnExpList 
            <-  Sp !END !ELSEIF !ELSE {| Exp (Sp ',' MaybeExp)* |}
            /   Sp {| %nil |}

If          <-  Sp ({} {| IfHead IfBody* |} NeedEnd)
            ->  If

IfHead      <-  Sp (IfPart     {}) -> IfBlock
            /   Sp (ElseIfPart {}) -> ElseIfBlock
            /   Sp (ElsePart   {}) -> ElseBlock
IfBody      <-  Sp (ElseIfPart {}) -> ElseIfBlock
            /   Sp (ElsePart   {}) -> ElseBlock
IfPart      <-  IF DirtyExp NeedThen
                    {| (!ELSEIF !ELSE !END Action)* |}
ElseIfPart  <-  ELSEIF DirtyExp NeedThen
                    {| (!ELSEIF !ELSE !END Action)* |}
ElsePart    <-  ELSE
                    {| (!ELSEIF !ELSE !END Action)* |}

For         <-  Loop / In

Loop        <-  LoopBody
            ->  Loop
LoopBody    <-  FOR LoopArgs NeedDo
                    {} {| (!END Action)* |}
                NeedEnd
LoopArgs    <-  MustName AssignOrEQ
                ({} {| (COMMA / !DO !END Exp->NoNil)* |} {})
            ->  PackLoopArgs

In          <-  InBody
            ->  In
InBody      <-  FOR InNameList NeedIn InExpList NeedDo
                    {} {| (!END Action)* |}
                NeedEnd
InNameList  <-  ({} {| (COMMA / !IN !DO !END Name->NoNil TypeAnn?)* |} {})
            ->  PackInNameList
InExpList   <-  ({} {| (COMMA / !DO !DO !END Exp->NoNil)*  |} {})
            ->  PackInExpList

While       <-  WhileBody
            ->  While
WhileBody   <-  WHILE DirtyExp NeedDo
                    {| (!END Action)* |}
                NeedEnd

Repeat      <-  (RepeatBody {})
            ->  Repeat
RepeatBody  <-  REPEAT
                    {| (!UNTIL Action)* |}
                NeedUntil DirtyExp

Local       <-  Sp ({} LOCAL LocalNameList ((AssignOrEQ ExpList) / %nil) {})
            ->  Local
Set         <-  Sp ({} SimpleList AssignOrEQ {} ExpList {}) 
            ->  Set
            /   Sp ({} SimpleList COMPASSIGN {} ExpList {}) 
            ->  CompSet

LocalNameList
            <-  {| LocalName (Sp ',' LocalName)* |}
LocalName   <-  (MustName TypeAnn?)
            ->  LocalName

NamedFunction
            <-  Function
            ->  NamedFunction

>>>>>>> origin/master
Call        <-  Simple
            ->  SimpleCall

LocalFunction
<<<<<<< HEAD
            <-  Sp ({} LOCAL FunctionNamedBody {})
            ->  LocalFunction

NamedFunction
            <-  Sp ({} FunctionNamedBody {})
            ->  NamedFunction
FunctionNamedBody
            <-  FUNCTION FuncName BlockStart FuncArg ReturnType?
                    (Emmy / !END Action)*
                    BlockEnd
                NeedEnd
FuncName    <-  (MustName (DOT MustName)* FuncMethod?)
            ->  Simple
FuncMethod  <-  COLON Name / COLON {} -> MissMethod

-- 占位
Emmy        <-  '---@'
]]

grammar 'Emmy' [[
Emmy            <-  EmmyAction
                /   EmmyComments
EmmyAction      <-  EmmySp '---' %s* '@' EmmyBody ShortComment
EmmySp          <-  (!'---' Comment / %s / %nl)*
EmmyComments    <-  EmmyComment+
                ->  EmmyComment
EmmyComment     <-  EmmySp '---' %s* !'@' {(!%nl .)*}
EmmyBody        <-  'class'    %s+ EmmyClass    -> EmmyClass
                /   'type'     %s+ EmmyType     -> EmmyType
                /   'alias'    %s+ EmmyAlias    -> EmmyAlias
                /   'param'    %s+ EmmyParam    -> EmmyParam
                /   'return'   %s+ EmmyReturn   -> EmmyReturn
                /   'field'    %s+ EmmyField    -> EmmyField
                /   'generic'  %s+ EmmyGeneric  -> EmmyGeneric
                /   'vararg'   %s+ EmmyVararg   -> EmmyVararg
                /   'language' %s+ EmmyLanguage -> EmmyLanguage
                /   'see'      %s+ EmmySee      -> EmmySee
                /   'overload' %s+ EmmyOverLoad -> EmmyOverLoad
                /   'module'   %s+ EmmyModule   -> EmmyModule
                /   EmmyIncomplete

EmmyName        <-  ({} {[a-zA-Z_] [a-zA-Z0-9_.]*})
                ->  EmmyName
MustEmmyName    <-  EmmyName / DirtyEmmyName
DirtyEmmyName   <-  {} ->  DirtyEmmyName
EmmyLongName    <-  ({} {(!%nl .)+})
                ->  EmmyName
EmmyIncomplete  <-  MustEmmyName
                ->  EmmyIncomplete

EmmyClass       <-  (MustEmmyName EmmyParentClass?)
EmmyParentClass <-  %s* {} ':' %s* MustEmmyName

EmmyType        <-  EmmyFunctionType
                /   EmmyTableType
                /   EmmyArrayType
                /   EmmyCommonType
EmmyCommonType  <-  EmmyTypeNames
                ->  EmmyCommonType
EmmyTypeNames   <-  EmmyTypeName (%s* {} '|' %s* !String EmmyTypeName)*
EmmyTypeName    <-  EmmyFunctionType
                /   EmmyTableType
                /   EmmyArrayType
                /   MustEmmyName
EmmyTypeEnum    <-  %s* (%nl %s* '---')? '|' EmmyEnum
                ->  EmmyTypeEnum
EmmyEnum        <-  %s* {'>'?} %s* String (EmmyEnumComment / (!%nl !'|' .)*)
EmmyEnumComment <-  %s* '#' %s* {(!%nl .)*}

EmmyAlias       <-  MustEmmyName %s* EmmyType EmmyTypeEnum*

EmmyParam       <-  MustEmmyName %s* EmmyType %s* EmmyOption %s* EmmyTypeEnum*
EmmyOption      <-  Table?
                ->  EmmyOption

EmmyReturn      <-  {} %nil     %nil                {} Table -> EmmyOption
                /   {} EmmyType (%s* EmmyName/%nil) {} EmmyOption

EmmyField       <-  (EmmyFieldAccess MustEmmyName %s* EmmyType)
EmmyFieldAccess <-  ({'public'}    Cut %s*)
                /   ({'protected'} Cut %s*)
                /   ({'private'}   Cut %s*)
                /   {} -> 'public'

EmmyGeneric     <-  EmmyGenericBlock
                    (%s* ',' %s* EmmyGenericBlock)*
EmmyGenericBlock<-  (MustEmmyName %s* (':' %s* EmmyType)?)
                ->  EmmyGenericBlock

EmmyVararg      <-  EmmyType

EmmyLanguage    <-  MustEmmyName

EmmyArrayType   <-  ({}    MustEmmyName -> EmmyCommonType {}      '[' DirtyBR)
                ->  EmmyArrayType
                /   ({} PL EmmyCommonType                 DirtyPR '[' DirtyBR)
                ->  EmmyArrayType

EmmyTableType   <-  ({} 'table' Cut '<' %s* EmmyType %s* ',' %s* EmmyType %s* '>' {})
                ->  EmmyTableType

EmmyFunctionType<-  ({} 'fun' Cut %s* EmmyFunctionArgs %s* EmmyFunctionRtns {})
                ->  EmmyFunctionType
EmmyFunctionArgs<-  ('(' %s* EmmyFunctionArg %s* (',' %s* EmmyFunctionArg %s*)* DirtyPR)
                ->  EmmyFunctionArgs
                /  '(' %nil DirtyPR -> None
                /   %nil
EmmyFunctionRtns<-  (':' %s* EmmyType (%s* ',' %s* EmmyType)*)
                ->  EmmyFunctionRtns
                /   %nil
EmmyFunctionArg <-  MustEmmyName %s* ':' %s* EmmyType

EmmySee         <-  {} MustEmmyName %s* '#' %s* MustEmmyName {}
EmmyOverLoad    <-  EmmyFunctionType
EmmyModule      <-  ({} {([a-zA-Z_] [a-zA-Z0-9_.]+ / '.' !'.')*} {})
=======
            <-  Sp ({} LOCAL Function)
            ->  LocalFunction
>>>>>>> origin/master
]]

grammar 'Lua' [[
Lua         <-  Head?
<<<<<<< HEAD
                (Emmy / Action)* -> Lua
                BlockEnd
=======
                ({} {| Action* |} {}) -> Lua
>>>>>>> origin/master
                Sp
Head        <-  '#' (!%nl .)*
]]

return function (self, lua, mode)
    local gram = compiled[mode] or compiled['Lua']
    local r, _, pos = gram:match(lua)
    if not r then
        local err = errorpos(pos)
        return nil, err
    end
<<<<<<< HEAD
=======
    if type(r) ~= 'table' then
        return nil
    end
>>>>>>> origin/master

    return r
end
