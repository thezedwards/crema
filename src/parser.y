%{
    #include "decls.h"
    #include "ast.h"
    #include "semantics.h"
    #include <stdlib.h>
    #include <stdio.h>

    NBlock *rootBlock;

    extern int yylex();
    void yyerror(const char *s) { fprintf(stderr, "ERROR: %s\n", s); exit(-1); }
%}

%define parse.error verbose

%union {
       NBlock *block;
       Node *node;
       int token;
       NIdentifier *ident;
       NExpression *expression;
       NStatement *statement;
       NVariableDeclaration *var_decl;
       std::vector<NVariableDeclaration*> *decl_args;
       std::vector<NExpression*> *call_args;
       std::string *string;
       int fn; /* which function */
}

/* Terminal types */
%token <string> TIDENTIFIER TINT TDOUBLE TSTRING TSTRUCT
%token <token> TRETURN TTRUE TFALSE TSDEF TDEF TIF TELSE TFOREACH TAS 
%token <token> TTVOID TTBOOL TTINT TTUINT TTDOUBLE TTSTR 
%token <token> TEQUAL TPERIOD TCOMMA TLPAREN TRPAREN TLBRAC TRBRAC TLBRACKET TRBRACKET TMOD
%token <token> TCEQ TCNEQ TCLE TCGE TCLT TCGT 
%token <token> TADD TSUB TMUL TDIV
%token <token> TAND TNOT TOR TUMINUS TUPLUS

/* Non-terminal types */
%type <token> type comparison combine def
%type <ident> identifier
%type <statement> statement struct_decl var_decl list_decl func_decl assignment return loop conditional
%type <expression> expression value numeric list_access struct list var_access
%type <block> block program statements 
%type <call_args> func_call_arg_list
%type <decl_args> func_decl_arg_list var_decls

%nonassoc TCEQ TCNEQ TCLE TCGE TCLT TCGT
%right TEQUAL
%left TADD TSUB
%left TMOD TMUL TDIV
%nonassoc TUMINUS TUPLUS /* this gives the unary minus precendence over the binary operators */ 

%start program

%%

program : { rootBlock = NULL; } /* Empty program */
    	| statements { rootBlock = $1; }
	    ;

statements : statement { $$ = new NBlock(); $$->statements.push_back($<statement>1); }
	       | statements statement { $1->statements.push_back($<statement>2); }
	       ;

statement : var_decl { }
	      | struct_decl { if(!rootCtx.registerStruct((NStructureDeclaration *) $1)) yyerror("Duplicate struct declaration!"); $$ = $1; }
	      | func_decl { if(!rootCtx.registerFunc((NFunctionDeclaration *) $1)) yyerror("Duplicate function declaration!"); $$ = $1; }
	      | assignment { }
	      | list_decl { }
	      | conditional { }
	      | loop { }
	      | return { }
	      ;

var_decls : { $$ = new VariableList(); }
	      | var_decl { $$ = new VariableList(); $$->push_back($<var_decl>1); }
	      | var_decls TCOMMA var_decl { $$->push_back($<var_decl>3); }
	      ;

var_decl : type identifier { $$ = new NVariableDeclaration(*(new Type($1)), *$2); }
	     | type identifier TEQUAL expression { $$ = new NVariableDeclaration(*(new Type($1)), *$2, $4); }
	     ;


struct_decl : TSTRUCT identifier TLBRACKET var_decls TRBRACKET { $$ = new NStructureDeclaration(*$2, *$4); }	
	        ;

func_decl : def type identifier TLPAREN func_decl_arg_list TRPAREN block { $$ = new NFunctionDeclaration(*(new Type($2)), *$3, *$5, $7); }
	      | def type TLBRAC TRBRAC identifier TLPAREN func_decl_arg_list TRPAREN block { $$ = new NFunctionDeclaration(*(new Type($2, true)), *$5, *$7, $9); }
	      ;

assignment : identifier TEQUAL expression { $$ = new NAssignmentStatement(*$1, *$3); }
	       | list_access TEQUAL expression { $$ = new NListAssignmentStatement(((NListAccess *) $1)->ident, *((NListAccess *) $1), *$3); }
	       | struct TEQUAL expression { $$ = new NStructureAssignmentStatement(((NStructureAccess *) $1)->ident, *((NStructureAccess *) $1), *$3); }
	       ;

list_decl : type identifier TLBRAC TRBRAC { Type *t = new Type($1, true); $$ = new NVariableDeclaration(*t, *$2); }
	      | type identifier TLBRAC TRBRAC TEQUAL expression { Type *t = new Type($1, true); $$ = new NVariableDeclaration(*t, *$2, $6); }
	      ;

conditional : TIF TLPAREN expression TRPAREN block TELSE conditional { $$ = new NIfStatement(*$3, *$5, $7); } /* else if */
	        | TIF TLPAREN expression TRPAREN block TELSE block { $$ = new NIfStatement(*$3, *$5, $7); } /* else */
	        | TIF TLPAREN expression TRPAREN block { $$ = new NIfStatement(*$3, *$5); } /* vanilla if */
	        ;

loop : TFOREACH TLPAREN identifier TAS identifier TRPAREN block { $$ = new NLoopStatement(*$3, *$5, *$7); }
     ;

return : TRETURN expression { $$ = new NReturn(*$2); }
       ;

def : TDEF
    | TSDEF
    ;

block : TLBRACKET statements TRBRACKET { $$ = $2; }
      | TLBRACKET TRBRACKET { $$ = new NBlock(); }
      ;

func_decl_arg_list : /* Empty */ { $$ = new VariableList(); }
		           | var_decl { $$ = new VariableList(); $$->push_back($<var_decl>1); }
		           | func_decl_arg_list TCOMMA var_decl { $$->push_back($<var_decl>3); }
		           ;

expression : expression TADD expression { $$ = new NBinaryOperator(*$1, $2, *$3); }
           | expression TSUB expression { $$ = new NBinaryOperator(*$1, $2, *$3); }
           | expression TMUL expression { $$ = new NBinaryOperator(*$1, $2, *$3); }
           | expression TDIV expression { $$ = new NBinaryOperator(*$1, $2, *$3); }
           | expression TMOD expression { $$ = new NBinaryOperator(*$1, $2, *$3); }
           | expression TAND expression { $$ = new NBinaryOperator(*$1, $2, *$3); }
           | expression TOR expression { $$ = new NBinaryOperator(*$1, $2, *$3); }
           | var_access { }
	       | var_access combine expression { $$ = new NBinaryOperator(*$1, $2, *$3); } 
	       | var_access comparison expression { $$ = new NBinaryOperator(*$1, $2, *$3); } 
           | identifier TLPAREN func_call_arg_list TRPAREN { $$ = new NFunctionCall(*$1, *$3); }
           | list { }
	       | TNOT expression { $$ = new NBinaryOperator(*$2, $1, *$2); }
	       | TLPAREN expression TRPAREN { $$ = $2; }
           | value { }
           ;

var_access : identifier { $$ = new NVariableAccess(*$1); }
	       | list_access { }
	       | struct { }
	       ;

list : TLBRAC func_call_arg_list TRBRAC { $$ = new NList(*$2); }
     ;

func_call_arg_list : /* Empty */ { $$ = new ExpressionList(); }
		           | expression { $$ = new ExpressionList(); $$->push_back($<expression>1); }
		           | func_call_arg_list TCOMMA expression { $$->push_back($<expression>3); }
		           ;

numeric : TINT { $$ = new NInt(atoi($1->c_str())); $$->type = *(new Type(TTINT)); delete $1; }
        | TDOUBLE { $$ = new NDouble(atof($1->c_str())); $$->type = *(new Type(TTDOUBLE)); delete $1; }
	    | TUMINUS TINT { NInt *zero = new NInt(0); zero->type = TTINT; 
                         NInt *i = new NInt(atoi($2->c_str())); i->type = *(new Type(TTINT)); 
                         delete $2; $$ = new NBinaryOperator(*zero, $1, *i); } 
        | TUMINUS TDOUBLE { NDouble *zero = new NDouble(0); zero->type = *(new Type(TTDOUBLE)); 
                            NDouble *d = new NDouble(atof($2->c_str())); d->type = Type(TTDOUBLE); 
                            delete $2; $$ = new NBinaryOperator(*zero, $1, *d); } 
        | TUPLUS TINT { NInt *zero = new NInt(0); zero->type = TTINT; 
                         NInt *i = new NInt(atoi($2->c_str())); i->type = *(new Type(TTINT)); 
                         delete $2; $$ = new NBinaryOperator(*zero, $1, *i); } 
        | TUPLUS TDOUBLE { NDouble *zero = new NDouble(0); zero->type = *(new Type(TTDOUBLE)); 
                            NDouble *d = new NDouble(atof($2->c_str())); d->type = Type(TTDOUBLE); 
                            delete $2; $$ = new NBinaryOperator(*zero, $1, *d); } 
        ;

value : numeric { $$ = $1; }
      | TSTRING { std::string str = $1->c_str(); $$ = new NString(str); $$->type = *(new Type(TTSTR)); delete $1; }
      | TTRUE { $$ = new NBool(true); $$->type = *(new Type(TTBOOL)); }
      | TFALSE { $$ = new NBool(false); $$->type = *(new Type(TTBOOL)); }
      ;

combine : TADD
	| TMUL
	| TMOD 
	| TSUB
	| TDIV
	| TOR
	| TAND
	;

list_access : identifier TLBRAC expression TRBRAC { $$ = new NListAccess(*$1, *$3); } /* Array access */
     	    ;

struct : identifier TPERIOD identifier { $$ = new NStructureAccess(*$1, *$3); } /* Structure access */
       ;

identifier : TIDENTIFIER { std::string str = $1->c_str(); $$ = new NIdentifier(str); delete $1; }
	   ;

comparison : TCEQ
	   | TCNEQ	
	   | TCGT
	   | TCLT
	   | TCGE
	   | TCLE
	   ;

type : TTDOUBLE
     | TTINT
     | TTUINT
     | TTSTR
     | TTVOID
     | TTBOOL
     ;

%%
