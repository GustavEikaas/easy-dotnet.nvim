; extends

; the structure of the queries in this document is as follows:
; 0. some comments if needed
; 1. sample code that matches the query
; 2. tree-sitter query

; NOTE: 
; queries for language injections for interpolated sql strings are not implemented intentionally. 

;;;;;;;;;;;;;;;;;;SQL;;;;;;;;;;;;;;;;;;

; //language=sql
; var sql = "select * from users";
(
(comment) @comment
.
(local_declaration_statement
  (variable_declaration
    (variable_declarator
      (string_literal
        (string_literal_content) @injection.content))))

(#eq? @comment "//language=sql")
(#set! injection.language "sql")
)

; var sql = "";
; //language=sql
; sql = "select * from users";
(
(comment) @comment
.
(expression_statement
  (assignment_expression
    (string_literal
      (string_literal_content) @injection.content)))

(#eq? @comment "//language=sql")
(#set! injection.language "sql")
)

; //language=sql
; var sql = @"select * from users";
(
(comment) @comment
.
(local_declaration_statement
  (variable_declaration
    (variable_declarator
      (verbatim_string_literal) @injection.content)))

(#eq? @comment "//language=sql")
(#set! injection.language "sql")
(#offset! @injection.content 0 2 0 -1)
)

; var sql = string.Empty;
; //language=sql
; sql = @"select * from users";
(
(comment) @comment
.
(expression_statement
  (assignment_expression
    (verbatim_string_literal) @injection.content))

(#eq? @comment "//language=sql")
(#set! injection.language "sql")
(#offset! @injection.content 0 2 0 -1)
)


; //language=sql
; var sql = """
;     select *
;     from users as u
;     inner join orders as o
;     """;
(
(comment) @comment
.
(local_declaration_statement
  (variable_declaration
    (variable_declarator
      (raw_string_literal
        (raw_string_content) @injection.content))))

(#eq? @comment "//language=sql")
(#set! injection.language "sql")
)

; var sql = string.Empty;
; //language=sql
; sql = """
;     select *
;     from users as u
;     inner join orders as o
;     """;
(
(comment) @comment
.
(expression_statement
  (assignment_expression
    (raw_string_literal
      (raw_string_content) @injection.content)))

(#eq? @comment "//language=sql")
(#set! injection.language "sql")
)

; TODO: validate that this injection is any good for general fallback
; (
;   [
;     (string_literal_content)
;     (raw_string_content)
;   ] @injection.content
;   (#match? @injection.content "(SELECT|select|INSERT|insert|UPDATE|update|DELETE|delete|UPSERT|upsert|DECLARE|declare).+(FROM|from|INTO|into|VALUES|values|SET|set).*(WHERE|where|GROUP BY|group by)?")
;   (#set! injection.language "sql")
; )

;;;;;;;;;;;;;;;;;;JSON;;;;;;;;;;;;;;;;;;

; TODO: implement injections for json

;;;;;;;;;;;;;;;;;;XML;;;;;;;;;;;;;;;;;;

; TODO: implement injections for xml
