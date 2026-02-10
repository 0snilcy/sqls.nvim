au BufRead,BufNewFile *.sqls_output set filetype=sqls_output

if exists("b:current_syntax")
  finish
endif

syntax sync fromstart

syntax match  SQLSTableBorder "[│─├┼┤┌┬┐└┴┘│]"
syntax match  SQLSTableNull   " <nil> "

highlight def link SQLSTableBorder FloatBorder
highlight def link SQLSTableNull Comment

let b:current_syntax = "sqls_output"

