module gen

import (
	strings
	v.ast
	v.table
	term
)

struct Gen {
	out         strings.Builder
	typedefs    strings.Builder
	definitions strings.Builder // typedefs, defines etc (everything that goes to the top of the file)
	table       &table.Table
mut:
	fn_decl     &ast.FnDecl // pointer to the FnDecl we are currently inside otherwise 0
	tmp_count   int
}

pub fn cgen(files []ast.File, table &table.Table) string {
	println('start cgen2')
	mut g := Gen{
		out: strings.new_builder(100)
		typedefs: strings.new_builder(100)
		definitions: strings.new_builder(100)
		table: table
		fn_decl: 0
	}
	g.init()
	for file in files {
		g.stmts(file.stmts)
	}
	return g.typedefs.str() + g.definitions.str() + g.out.str()
}

pub fn (g mut Gen) init() {
	g.definitions.writeln('// Generated by the V compiler')
	g.definitions.writeln('#include <inttypes.h>') // int64_t etc
	g.definitions.writeln(c_builtin_types)
	g.definitions.writeln(c_headers)
	// Multi return structs
	// TODO move to a method
	g.definitions.writeln('// multi return structs')
	for typ in g.table.types {
		// sym := g.table.get_type_symbol(typ)
		if typ.kind != .multi_return {
			continue
		}
		name := typ.name.replace('.', '__')
		info := typ.info as table.MultiReturn
		g.definitions.writeln('typedef struct {')
		// TODO copy pasta StructDecl
		// for field in struct_info.fields {
		for i, mr_typ in info.types {
			field_type_sym := g.table.get_type_symbol(mr_typ)
			type_name := field_type_sym.name.replace('.', '__')
			g.definitions.writeln('\t$type_name arg${i};')
		}
		g.definitions.writeln('} $name;\n')
		// g.typedefs.writeln('typedef struct $name $name;')
	}
	g.definitions.writeln('// end of definitions #endif')
}

pub fn (g &Gen) save() {}

pub fn (g mut Gen) write(s string) {
	g.out.write(s)
}

pub fn (g mut Gen) writeln(s string) {
	g.out.writeln(s)
}

pub fn (g mut Gen) new_tmp_var() string {
	g.tmp_count++
	return 'tmp$g.tmp_count'
}

pub fn (g mut Gen) reset_tmp_count() {
	g.tmp_count = 0
}

fn (g mut Gen) stmts(stmts []ast.Stmt) {
	for stmt in stmts {
		g.stmt(stmt)
		g.writeln('')
	}
}

fn (g mut Gen) stmt(node ast.Stmt) {
	// println('cgen.stmt()')
	// g.writeln('//// stmt start')
	match node {
		ast.AssignStmt {
			// ident0 := it.left[0]
			// info0 := ident0.var_info()
			// for i, ident in it.left {
			// info := ident.var_info()
			// if info0.typ.typ.kind == .multi_return {
			// if i == 0 {
			// g.write('$info.typ.typ.name $ident.name = ')
			// g.expr(it.right[0])
			// } else {
			// arg_no := i-1
			// g.write('$info.typ.typ.name $ident.name = $ident0.name->arg[$arg_no]')
			// }
			// }
			// g.writeln(';')
			// }
			g.write('') // /*assign*/')
		}
		ast.AssertStmt {
			g.write('// assert')
			// TODO
		}
		ast.Attr {
			g.writeln('//[$it.name]')
		}
		ast.BranchStmt {
			// continue or break
			g.write(it.tok.kind.str())
			g.writeln(';')
		}
		ast.ConstDecl {
			for i, field in it.fields {
				field_type_sym := g.table.get_type_symbol(field.typ)
				name := field.name.replace('.', '__')
				g.write('$field_type_sym.name $name = ')
				g.expr(it.exprs[i])
				g.writeln(';')
			}
		}
		ast.CompIf {
			// TODO
			g.writeln('//#ifdef ')
			g.expr(it.cond)
			g.stmts(it.stmts)
			g.writeln('//#endif')
		}
		ast.DeferStmt {
			g.writeln('// defer')
		}
		ast.EnumDecl {
			g.writeln('typedef enum {')
			for i, val in it.vals {
				g.writeln('\t${it.name}_$val, // $i')
			}
			g.writeln('} $it.name;')
		}
		ast.ExprStmt {
			g.expr(it.expr)
			match it.expr {
				// no ; after an if expression
				ast.IfExpr {}
				else {
					g.writeln(';')
				}
	}
		}
		ast.FnDecl {
			if it.is_c || it.name == 'malloc' {
				return
			}
			g.reset_tmp_count()
			g.fn_decl = it // &it
			is_main := it.name == 'main'
			if is_main {
				g.write('int ${it.name}(')
			}
			else {
				type_sym := g.table.get_type_symbol(it.typ)
				mut name := it.name
				if it.is_method {
					name = g.table.get_type_symbol(it.receiver.typ).name + '_' + name
				}
				name = name.replace('.', '__')
				// type_name := g.table.type_to_str(it.typ)
				type_name := type_sym.name.replace('.', '__') // g.table.type_to_str(it.typ)
				g.write('$type_name ${name}(')
				g.definitions.write('$type_name ${name}(')
			}
			// Receiver is the first argument
			if it.is_method {
				// styp := g.table.type_to_str(it.receiver.typ)
				sym := g.table.get_type_symbol(it.receiver.typ)
				styp := sym.name.replace('.', '__')
				g.write('$styp $it.receiver.name')
				if it.args.len > 0 {
					g.write(', ')
				}
			}
			//
			no_names := it.args.len > 0 && it.args[0].name == 'arg_1'
			for i, arg in it.args {
				arg_type_sym := g.table.get_type_symbol(arg.typ)
				mut arg_type_name := arg_type_sym.name.replace('.', '__')
				if i == it.args.len - 1 && it.is_variadic {
					arg_type_name = 'variadic_$arg_type_name'
				}
				if no_names {
					g.write(arg_type_name)
					g.definitions.write(arg_type_name)
				}
				else {
					g.write(arg_type_name + ' ' + arg.name)
					g.definitions.write(arg_type_name + ' ' + arg.name)
				}
				if i < it.args.len - 1 {
					g.write(', ')
					g.definitions.write(', ')
				}
			}
			g.writeln(') { ')
			if !is_main {
				g.definitions.writeln(');')
			}
			for stmt in it.stmts {
				g.stmt(stmt)
			}
			if is_main {
				g.writeln('return 0;')
			}
			g.writeln('}')
			g.fn_decl = 0
		}
		ast.ForCStmt {
			g.write('for (')
			g.stmt(it.init)
			// g.write('; ')
			g.expr(it.cond)
			g.write('; ')
			// g.stmt(it.inc)
			g.expr(it.inc)
			g.writeln(') {')
			for stmt in it.stmts {
				g.stmt(stmt)
			}
			g.writeln('}')
		}
		ast.ForInStmt {
			if it.is_range {
				i := g.new_tmp_var()
				g.write('for (int $i = ')
				g.expr(it.cond)
				g.write('; $i < ')
				g.expr(it.high)
				g.writeln('; $i++) { ')
				// g.stmts(it.stmts) TODO
				g.writeln('}')
			}
		}
		ast.ForStmt {
			g.write('while (')
			g.expr(it.cond)
			g.writeln(') {')
			for stmt in it.stmts {
				g.stmt(stmt)
			}
			g.writeln('}')
		}
		ast.GlobalDecl {
			// TODO
			g.writeln('__global')
		}
		ast.GotoLabel {
			g.writeln('$it.name:')
		}
		ast.HashStmt {
			// #include etc
			g.writeln('#$it.val')
		}
		ast.Import {}
		ast.Return {
			g.write('return')
			// multiple returns
			if it.exprs.len > 1 {
				type_sym := g.table.get_type_symbol(g.fn_decl.typ)
				g.write(' ($type_sym.name){')
				for i, expr in it.exprs {
					g.write('.arg$i=')
					g.expr(expr)
					if i < it.exprs.len - 1 {
						g.write(',')
					}
				}
				g.write('}')
			}
			// normal return
			else if it.exprs.len == 1 {
				g.write(' ')
				g.expr(it.exprs[0])
			}
			g.writeln(';')
		}
		ast.StructDecl {
			name := it.name.replace('.', '__')
			g.writeln('typedef struct {')
			for field in it.fields {
				field_type_sym := g.table.get_type_symbol(field.typ)
				g.writeln('\t$field_type_sym.name $field.name;')
			}
			g.writeln('} $name;')
			g.typedefs.writeln('typedef struct $name $name;')
		}
		ast.TypeDecl {
			g.writeln('// type')
		}
		ast.UnsafeStmt {
			g.stmts(it.stmts)
		}
		ast.VarDecl {
			type_sym := g.table.get_type_symbol(it.typ)
			styp := type_sym.name.replace('.', '__')
			g.write('$styp $it.name = ')
			g.expr(it.expr)
			g.writeln(';')
		}
		else {
			verror('cgen.stmt(): unhandled node ' + typeof(node))
		}
	}
}

fn (g mut Gen) expr(node ast.Expr) {
	// println('cgen expr() line_nr=$node.pos.line_nr')
	match node {
		ast.ArrayInit {
			type_sym := g.table.get_type_symbol(it.typ)
			elem_sym := g.table.get_type_symbol(it.elem_type)
			g.write('new_array_from_c_array($it.exprs.len, $it.exprs.len, sizeof($type_sym.name), ')
			g.writeln('(${elem_sym.name}[]){\t')
			for expr in it.exprs {
				g.expr(expr)
				g.write(', ')
			}
			g.write('\n})')
		}
		ast.AsCast {
			g.write('/* as */')
		}
		ast.AssignExpr {
			g.expr(it.left)
			g.write(' $it.op.str() ')
			g.expr(it.val)
		}
		ast.Assoc {
			g.write('/* assoc */')
		}
		ast.BoolLiteral {
			g.write(it.val.str())
		}
		ast.CallExpr {
			mut name := it.name.replace('.', '__')
			if it.is_c {
				// Skip "C__"
				name = name[3..]
			}
			g.write('${name}(')
			g.call_args(it.args)
			g.write(')')
			/*
			for i, expr in it.args {
				g.expr(expr)
				if i != it.args.len - 1 {
					g.write(', ')
				}
			}
			*/

		}
		ast.CastExpr {
			styp := g.table.type_to_str(it.typ)
			g.write('($styp)(')
			g.expr(it.expr)
			g.write(')')
		}
		ast.CharLiteral {
			g.write("'$it.val'")
		}
		ast.EnumVal {
			g.write('${it.enum_name}_$it.val')
		}
		ast.FloatLiteral {
			g.write(it.val)
		}
		ast.Ident {
			name := it.name.replace('.', '__')
			g.write(name)
		}
		ast.IfExpr {
			// If expression? Assign the value to a temp var.
			// Previously ?: was used, but it's too unreliable.
			type_sym := g.table.get_type_symbol(it.typ)
			mut tmp := ''
			if type_sym.kind != .void {
				tmp = g.new_tmp_var()
				// g.writeln('$ti.name $tmp;')
			}
			// one line ?:
			// TODO clean this up once `is` is supported
			if it.stmts.len == 1 && it.else_stmts.len == 1 && type_sym.kind != .void {
				cond := it.cond
				stmt1 := it.stmts[0]
				else_stmt1 := it.else_stmts[0]
				match stmt1 {
					ast.ExprStmt {
						g.expr(cond)
						g.write(' ? ')
						expr_stmt := stmt1 as ast.ExprStmt
						g.expr(expr_stmt.expr)
						g.write(' : ')
						g.stmt(else_stmt1)
					}
					else {}
	}
			}
			else {
				g.write('if (')
				g.expr(it.cond)
				g.writeln(') {')
				for i, stmt in it.stmts {
					// Assign ret value
					if i == it.stmts.len - 1 && type_sym.kind != .void {}
					// g.writeln('$tmp =')
					g.stmt(stmt)
				}
				g.writeln('}')
				if it.else_stmts.len > 0 {
					g.writeln('else { ')
					for stmt in it.else_stmts {
						g.stmt(stmt)
					}
					g.writeln('}')
				}
			}
		}
		ast.IfGuardExpr {
			g.write('/* guard */')
		}
		ast.IndexExpr {
			g.index_expr(it)
		}
		ast.InfixExpr {
			g.expr(it.left)
			if it.op == .dot {
				println('!! dot')
			}
			g.write(' $it.op.str() ')
			g.expr(it.right)
			// if typ.name != typ2.name {
			// verror('bad types $typ.name $typ2.name')
			// }
		}
		ast.IntegerLiteral {
			g.write(it.val.str())
		}
		ast.MatchExpr {
			// println('match expr typ=$it.expr_type')
			// TODO
			if it.expr_type == 0 {
				g.writeln('// match 0')
				return
			}
			type_sym := g.table.get_type_symbol(it.expr_type)
			mut tmp := ''
			if type_sym.kind != .void {
				tmp = g.new_tmp_var()
			}
			g.write('$type_sym.name $tmp = ')
			g.expr(it.cond)
			g.writeln(';') // $it.blocks.len')
			for branch in it.branches {
				g.write('if ')
				for i, expr in branch.exprs {
					g.write('$tmp == ')
					g.expr(expr)
					if i < branch.exprs.len - 1 {
						g.write(' || ')
					}
				}
				g.writeln('{')
				g.stmts(branch.stmts)
				g.writeln('}')
			}
		}
		ast.MethodCallExpr {
			typ := 'TODO'
			name := it.name.replace('.', '__')
			g.write('${typ}_${name}(')
			g.expr(it.expr)
			if it.args.len > 0 {
				g.write(', ')
			}
			g.call_args(it.args)
			g.write(')')
		}
		ast.None {
			g.write('0')
		}
		ast.ParExpr {
			g.write('(')
			g.expr(it.expr)
			g.write(')')
		}
		ast.PostfixExpr {
			g.expr(it.expr)
			g.write(it.op.str())
		}
		ast.PrefixExpr {
			g.write(it.op.str())
			g.expr(it.right)
		}
		/*
		ast.UnaryExpr {
			// probably not :D
			if it.op in [.inc, .dec] {
				g.expr(it.left)
				g.write(it.op.str())
			}
			else {
				g.write(it.op.str())
				g.expr(it.left)
			}
		}
		*/

		ast.SizeOf {
			g.write('sizeof($it.type_name)')
		}
		ast.StringLiteral {
			g.write('tos3("$it.val")')
		}
		// `user := User{name: 'Bob'}`
		ast.StructInit {
			type_sym := g.table.get_type_symbol(it.typ)
			g.writeln('($type_sym.name){')
			for i, field in it.fields {
				g.write('\t.$field = ')
				g.expr(it.exprs[i])
				g.writeln(', ')
			}
			g.write('}')
		}
		ast.SelectorExpr {
			g.expr(it.expr)
			g.write('.')
			g.write(it.field)
		}
		ast.Type {
			g.write('/* Type */')
		}
		else {
			// #printf("node=%d\n", node.typ);
			println(term.red('cgen.expr(): bad node ' + typeof(node)))
		}
	}
}

fn (g mut Gen) index_expr(node ast.IndexExpr) {
	// TODO else doesn't work with sum types
	mut is_range := false
	match node.index {
		ast.RangeExpr {
			is_range = true
			g.write('array_slice(')
			g.expr(node.left)
			g.write(', ')
			// g.expr(it.low)
			g.write('0')
			g.write(', ')
			g.expr(it.high)
			g.write(')')
		}
		else {}
	}
	if !is_range {
		g.expr(node.left)
		g.write('[')
		g.expr(node.index)
		g.write(']')
	}
}

fn (g mut Gen) call_args(args []ast.Expr) {
	for i, expr in args {
		g.expr(expr)
		if i != args.len - 1 {
			g.write(', ')
		}
	}
}

fn verror(s string) {
	println('cgen error: $s')
	// exit(1)
}
