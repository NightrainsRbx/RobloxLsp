local re = require 'parser.relabel'
local m = require 'lpeglabel'
local ast = require 'parser.ast'

local scriptBuf = ''
local compiled = {}
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
defs['true'] = m.Cp() / function () return true end
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
defs.NoNil = function (o)
    if o == nil then
        return
    end
    return o
end

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
Comment         <-  LongComment
                /   '--' ShortComment
LongComment     <-  ({} '--[' {} {:eq: '='* :} {} '[' %nl?
                    {(!CommentClose .)*}
                    ((CommentClose / %nil) {}))
                ->  LongComment
CommentClose    <-  {']' =eq ']'}
ShortComment    <-  ({} {(!%nl .)*} {})
                ->  ShortComment
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
FALSE       <-  Sp 'false'    Cut
LOCAL       <-  Sp 'local'    Cut
NIL         <-  Sp 'nil'      Cut
NOT         <-  Sp 'not'      Cut
OR          <-  Sp {'or'}     Cut
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
POWER       <-  Sp {'^'}

BinaryOp    <-( Sp {} {'or'} Cut
            /   Sp {} {'and'} Cut
            /   Sp {} {'<=' / '>=' / '<'!'<' / '>'!'>' / '~=' / '==' !'='}
            /   Sp {} ({} ('=' !'=' / '===') {}) -> ErrEQ
            /   Sp {} ({} '!=' '='? {}) -> ErrUEQ
            /   Sp {} {'..'} !'.'
            /   Sp {} {'+' / '-'}
            /   Sp {} {'*' / '/' / '%'}
            /   Sp {} {'^'}
            )-> BinaryOp
UnaryOp     <-( Sp {} {'not' Cut / '#' / '-' !'-'}
            )-> UnaryOp

PL          <-  Sp '('
PR          <-  Sp ')'
BL          <-  Sp '[' !'[' !'='
BR          <-  Sp ']'
TL          <-  Sp '{'
TR          <-  Sp '}'
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
NeedEnd     <-  END    / {} -> MissEnd
NeedDo      <-  DO     / {} -> MissDo
NeedAssign  <-  ASSIGN / {} -> MissAssign
NeedComma   <-  COMMA  / {} -> MissComma
NeedIn      <-  IN     / {} -> MissIn
NeedUntil   <-  UNTIL  / {} -> MissUntil
NeedThen    <-  THEN   / {} -> MissThen
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
                ErrNumber?
NumberDef   <-  Number16 / Number2 / Number10
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
NameStr     <-  [a-zA-Z_] [a-zA-Z0-9_]*
NameBody    <-  {NameStr}
FreeName    <-  Sp ({} {NameBody=>NotReserved} {})
            ->  Name
KeyWord     <-  Sp NameBody=>Reserved
MustName    <-  Name / DirtyName
DirtyName   <-  {} -> DirtyName
]]

grammar 'Exp' [[
Exp         <-  (UnUnit BinUnit*)
            ->  Binary
BinUnit     <-  (BinaryOp UnUnit?)
            ->  SubBinary
UnUnit      <-  TypeAssert
            /   (UnaryOp+ (TypeAssert / MissExp))
            ->  Unary
TypeAssert  <-  (ExpUnit (LABEL Type)?)
            ->  TypeAssert
ExpUnit     <-  Nil
            /   Boolean
            /   String
            /   InterString
            /   Number
            /   Dots
            /   Table
            /   ExpFunction
            /   IfExp
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
            <-  (DOT (FreeName / MissField))
            ->  GetField
            /   ({} BL DirtyExp DirtyBR {})
            ->  GetIndex
            /   (COLON (FreeName / MissMethod) NeedCall)
            ->  GetMethod
            /   ({} {| Table |} {})
            ->  Call
            /   ({} {| String |} {})
            ->  Call
NeedCall    <-  (!(Sp CallStart) {} -> MissPL)?
MissField   <-  {} -> MissField
MissMethod  <-  {} -> MissMethod
CallStart   <-  PL
            /   TL
            /   '"'
            /   AL
            /   "'"
            /   '[' '='* '['

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
            <-  FUNCTION FuncName GenericsDef FuncArgs {} ReturnTypeAnn
                    {| (!END Action)* |}
                NeedEnd
            /   FUNCTION FuncName GenericsDef FuncArgsMiss {} ReturnTypeAnn
                    {| %nil |}
                NeedEnd
FuncName    <-  !END {| Single (Sp SuffixWithoutCall)* |}
            ->  Simple
            /   %nil

FuncArgs    <-  Sp ({} PL {| FuncArg+ |} DirtyPR {})
            ->  FuncArgs
            /   PL DirtyPR %nil
FuncArgsMiss<-  {} -> MissPL DirtyPR %nil
FuncArg     <-  DOTS DotsTypeAnn?
            /   Name TypeAnn?
            /   COMMA

IfExp       <-  Sp (IF DirtyExp (THEN / {} -> MissThen) DirtyExp {| ElseIfExp* |} (ELSE / {} -> MissElse) DirtyExp {})
            ->  IfExp

ElseIfExp   <-  Sp (ELSEIF DirtyExp (THEN / {} -> MissThen) DirtyExp {})
            ->  ElseIfExp

-- 纯占位，修改了 `relabel.lua` 使重复定义不抛错
Action      <-  !END .

InterString <-  Sp ({} InterStringDef {})
            ->  InterString
InterStringDef
            <-  {'`'}
                {| (InterStr / {~ (Esc / !InterStr !%nl !'`' .)+ ~})* |}
                ('`' / {} -> MissQuote3)
InterStr    <-  '{' DirtyExp DirtyTR

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

TypeUnit    <-  ModuleType
            /   Typeof
            /   SingletonType
            /   NameType
            /   FuncType
            /   TableType
            /   TypeSimple

TypeSimple  <-  ({| TypeOrParen |} Optional?)
            ->  TypeSimple
TypeOrParen <-  Sp ({} PL Type !COMMA DirtyPR {})
            ->  Paren
            /   Single

DirtyType   <-  Type
            /   {} -> DirtyType

Typeof      <-  Sp ({} 'typeof' Sp {} PL Exp DirtyPR {} Optional?)
            ->  Typeof

DefaultType <-  Sp ({} AssignOrEQ Type {})
            ->  DefaultType
DefaultTypePack 
            <-  Sp ({} AssignOrEQ (VariadicType / TypeList) {})
            ->  DefaultType
GenericsDef <-  Sp ({} AL Sp {| (GenericPackType DefaultTypePack? / Name DefaultType? / COMMA)+ |} Sp DirtyAR {})
            ->  GenericsDef
            /   %nil
Generics    <-  Sp ({} AL Sp {| (VariadicType / Type / TypeList / COMMA)* |} Sp DirtyAR {})
            ->  Generics
            /   %nil
TypeList    <-  Sp ({} PL {| (VariadicType / Type / COMMA)* |} DirtyPR {})
            ->  TypeList
NamedType   <-  Sp (Name COLON Type) 
            ->  NamedType
ArgTypeList <-  Sp ({} PL {| (NamedType / VariadicType / Type / COMMA)* |} DirtyPR {})
            ->  TypeList
ModuleType  <-  Sp ({} (Name -> Single) DOT (NameType / %nil) {})
            ->  ModuleType
NameType    <-  Sp ({} NameBody Generics {} Optional?)
            ->  NameType
FuncType    <-  Sp ({} GenericsDef ArgTypeList ARROW (VariadicType / Type !DOTS / TypeList) Optional? {})
            ->  FuncType
VariadicType    
            <-  Sp ({} DOTS Type {})
            ->  VariadicType
            /   GenericPackType
GenericPackType
            <-  Sp (Name DOTS)
            ->  GenericPackType
SingletonType
            <-  ((String / Boolean) Optional?)
            ->  SingletonType

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
DotsTypeAnn <-  (COLON {} (GenericPackType / Type) {})
            ->  TypeAnn            
ReturnTypeAnn
            <-  (COLON {} (VariadicType / Type !DOTS / TypeList) {})
            ->  TypeAnn
            /   %nil
]]

grammar 'Action' [[
Action      <-  Sp (CrtAction / UnkAction)
CrtAction   <-  Semicolon
            /   Do
            /   Break
            /   Return
            /   If
            /   For
            /   While
            /   Repeat
            /   NamedFunction
            /   LocalFunction
            /   Local
            /   TypeAlias
            /   Set
            /   Continue
            /   Call
            /   ExpInAction
UnkAction   <-  ({} {Word+})
            ->  UnknownAction
            /   ({} {. (!Sps !CrtAction .)*})
            ->  UnknownAction
ExpInAction <-  Sp ({} Exp {})
            ->  ExpInAction

Semicolon   <-  Sp ';'
SimpleList  <-  {| Simple (Sp ',' Simple)* |}

TypeAliasName
            <-  (Sp ({} ({NameStr '.' NameStr} / NameBody) {}))
            ->  Name

TypeAlias   <-  Sp ({} (EXPORT %true / %false) TYPE TypeAliasName GenericsDef AssignOrEQ DirtyType {})
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
LoopArgs    <-  MustName (TypeAnn / %nil) AssignOrEQ
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

Call        <-  Simple
            ->  SimpleCall

LocalFunction
            <-  Sp ({} LOCAL Function)
            ->  LocalFunction
]]

grammar 'Lua' [[
Lua         <-  Head?
                ({} {| Action* |} {}) -> Lua
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
    if type(r) ~= 'table' then
        return nil
    end

    return r
end
