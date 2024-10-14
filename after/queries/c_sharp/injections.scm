; extends

; the structure of the queries in this document is as follows:
; 0. sample code that matches the query
; 1. some comments if needed
; 2. tree-sitter query

; NOTE: 
; queries for language injections for interpolated sql strings are not implemented intentionally. 

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;SQL;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;JSON;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; //language=json
; var json = """
;     {
;       "product": {
;         "id": "p123",
;         "name": "Laptop",
;         "price": 999.99,
;         "inStock": true
;       }
;     }
;     """;
(
(comment) @comment
.
(local_declaration_statement
  (variable_declaration
    (variable_declarator
      (raw_string_literal
        (raw_string_content) @injection.content))))

(#eq? @comment "//language=json")
(#set! injection.language "json")
)

; var json = string.Empty;
; //language=json
; json = """
;     {
;       "product": {
;         "id": "p123",
;         "name": "Laptop",
;         "price": 999.99,
;         "inStock": true
;       }
;     }
;     """;
(
(comment) @comment
.
(expression_statement
  (assignment_expression
    (raw_string_literal
      (raw_string_content) @injection.content)))

(#eq? @comment "//language=json")
(#set! injection.language "json")
)

; var name = "Emma";
; //language=json
; var raw2 = $$"""
;     {
;       "person": {
;         "name": {{name}},
;         "age": 28,
;         "hobbies": ["reading", "swimming"]
;       }
;     }
;     """;
; TODO: investigate if it is correct that all strings in a file are parsed as one document. And if it is not, then fix the use of injection.combined
(
(comment) @comment
.
(local_declaration_statement
  (variable_declaration
    (variable_declarator
      (interpolated_string_expression
        (string_content) @injection.content))))

(#eq? @comment "//language=json")
(#set! injection.language "json")
(#set! injection.combined)
)

; var price = 999.99;
; var raw3 = string.Empty;
; //language=json
; raw3 = $$"""
;     {
;       "product": {
;         "id": "p123",
;         "name": "Laptop",
;         "price": {{price}},
;         "inStock": true
;       }
;     }
;     """;
; TODO: investigate if it is correct that all strings in a file are parsed as one document. And if it is not, then fix the use of injection.combined
(
(comment) @comment
.
(expression_statement
  (assignment_expression
    (interpolated_string_expression
      (string_content) @injection.content)))

(#eq? @comment "//language=json")
(#set! injection.language "json")
(#set! injection.combined)
)

; TODO: validate that this injection is any good for general fallback
; (
;   [
;     (string_literal_content)
;     (raw_string_content)
;   ] @injection.content
;   (#match? @injection.content "^\\s*\\{.*\\}\\s*$")
;   (#set! injection.language "json")
; )

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;XML;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; //language=xml
; var xml = """
;     <person>
;       <name>John Doe</name>
;       <age>30</age>
;     </person>
;     """;
(
(comment) @comment
.
(local_declaration_statement
  (variable_declaration
    (variable_declarator
      (raw_string_literal
        (raw_string_content) @injection.content))))

(#eq? @comment "//language=xml")
(#set! injection.language "xml")
)

; var xml = string.Empty;
; //language=xml
; xml = """
;     <?xml version="1.0" encoding="UTF-8"?>
;     <book>
;       <title>The Great Gatsby</title>
;       <author>F. Scott Fitzgerald</author>
;       <year>1925</year>
;     </book>
;     """;
(
(comment) @comment
.
(expression_statement
  (assignment_expression
    (raw_string_literal
      (raw_string_content) @injection.content)))

(#eq? @comment "//language=xml")
(#set! injection.language "xml")
)

; var title = "The Great Gatsby";
; var author = "F. Scott Fitzgerald";
; //language=xml
; var xml2 = $"""
;     <?xml version="1.0" encoding="UTF-8"?>
;     <book>
;       <title>{title}</title>
;       <author>{author}</author>
;       <year>1925</year>
;     </book>
;     """;
; TODO: investigate if it is correct that all strings in a file are parsed as one document. And if it is not, then fix the use of injection.combined
(
(comment) @comment
.
(local_declaration_statement
  (variable_declaration
    (variable_declarator
      (interpolated_string_expression
        (string_content) @injection.content))))

(#eq? @comment "//language=xml")
(#set! injection.language "xml")
(#set! injection.combined)
)

; var userId = 1;
; var email = "alice@example.com";
; var xml3 = string.Empty;
; //language=xml
; xml3 = $$"""
;     <users>
;       <user id="{userId}">
;         <name>Alice</name>
;         <email>{email}</email>
;       </user>
;     </users>
;     """;
; TODO: investigate if it is correct that all strings in a file are parsed as one document. And if it is not, then fix the use of injection.combined
(
(comment) @comment
.
(expression_statement
  (assignment_expression
    (interpolated_string_expression
      (string_content) @injection.content)))

(#eq? @comment "//language=xml")
(#set! injection.language "xml")
(#set! injection.combined)
)

; TODO: validate that this injection is any good for general fallback
; (
;   (raw_string_content) @injection.content
;   (#match? @injection.content "^\\s*<[^>]+>")
;   (#set! injection.language "xml")
; )
