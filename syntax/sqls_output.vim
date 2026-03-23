au BufRead,BufNewFile *.sqls_output set filetype=sqls_output

if exists("b:current_syntax")
  finish
endif

syntax sync fromstart

syntax match  SQLSTableBorder "[│─├┼┤┌┬┐└┴┘│]"
syntax match  SQLSTableNull   " <nil> "
syntax match  SQLSTableSep   " | "
syntax match  SQLSTableSpace   "∙"




highlight def link SQLSTableBorder FloatBorder
highlight def link SQLSTableNull Comment
highlight def link SQLSTableSpace Comment
highlight def link SQLSTableSep FloatBorder


let b:current_syntax = "sqls_output"

