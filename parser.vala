using Gee;

abstract class Node : Object {
	public int start;
	public int end;
	
	Node(int start, int end) {
		this.start = start;
		this.end = end;
	}
	
	// Return all children which may possibly contain a scope.
	public virtual ArrayList<Node>? children() { return null; }
	
	protected Chain? find(Chain? parent, int pos) {
		Chain c = parent;
		Scope s = this as Scope;
		if (s != null)
			c = new Chain(s, parent);	// link this scope in
			
		ArrayList<Node> nodes = children();
		if (nodes != null)
			foreach (Node n in nodes)
				if (n.start <= pos && pos <= n.end)
					return n.find(c, pos);
		return c;
	}
	
	public abstract void print(int level);

	protected void do_print(int level, string s) {
		stdout.printf("%s%s\n", string.nfill(level * 2, ' '), s);
	}	
}

abstract class Symbol : Node {
	public string name;
	
	public Symbol(string name, int start, int end) {
		base(start, end);
		this.name = name;
	}
	
	public static Symbol? lookup_in_array(ArrayList<Symbol> a, string name) {
		foreach (Symbol s in a)
			if (s.name == name)
				return s;
		return null;
	}
	
	protected void print_name(int level, string s) {
		do_print(level, s + " " + name);
	}
}

abstract class TypeSymbol : Symbol {
	public TypeSymbol(string name, int start, int end) { base(name, start, end); }
}

abstract class Statement : Node {
	public Statement(int start, int end) { base(start, end); }
	
	public virtual Symbol? defines_symbol(string name) { return null; }
}

abstract class DataType : Node {
	public abstract string to_string();
	public override void print(int level) { }
}

class TypeName : DataType {
	public string name;
	
	public TypeName(string name) { this.name = name; }
	
	public override string to_string() { return name; }
}

abstract class Variable : Symbol {
	DataType type;
	
	public Variable(DataType type, string name, int start, int end) {
		base(name, start, end);
		this.type = type;
	}
	
	protected abstract string kind();
	
	public override void print(int level) {
		print_name(level, kind() + " " + type.to_string());
	}
}

class LocalVariable : Variable {
	public LocalVariable(DataType type, string name, int start, int end) {
		base(type, name, start, end);
	}
	
	protected override string kind() { return "local"; }
}

class DeclarationStatement : Statement {
	public LocalVariable variable;
	
	public DeclarationStatement(LocalVariable variable, int start, int end) {
		base(start, end);
		this.variable = variable;
	}
	
	public override Symbol? defines_symbol(string name) {
		return variable.name == name ? variable : null;
	}
	
	public override void print(int level) {
		variable.print(level);
	}
}

interface Scope : Object {
	public abstract Symbol? lookup(string name, int pos);
}

class Chain {
	Scope scope;
	Chain parent;
	
	public Chain(Scope scope, Chain? parent) {
		this.scope = scope;
		this.parent = parent;
	}
	
	public Symbol? lookup(string name, int pos) {
		Symbol s = scope.lookup(name, pos);
		if (s != null)
			return s;
		return parent == null ? null : parent.lookup(name, pos);
	}
}

class Block : Statement, Scope {
	public ArrayList<Statement> statements = new ArrayList<Statement>();

	public override ArrayList<Node>? children() { return statements; }
	
	Symbol? lookup(string name, int pos) {
		foreach (Statement s in statements) {
			if (s.start > pos)
				return null;
			Symbol sym = s.defines_symbol(name);
			if (sym != null)
				return sym;
		}
		return null;
	}
	
	protected override void print(int level) {
		do_print(level, "block");
		
		foreach (Statement s in statements)
			s.print(level + 1);
	}
}

class Parameter : Variable {
	public Parameter(DataType type, string name, int start, int end) {
		base(type, name, start, end);
	}
	
	protected override string kind() { return "parameter"; }
}

class Method : Symbol, Scope {
	public ArrayList<Parameter> parameters = new ArrayList<Parameter>();
	public Block body;
	
	public Method(string name) { base(name, 0, 0); }
	
	public override ArrayList<Node>? children() {
		if (body == null)
			return null;
			
		ArrayList<Node> a = new ArrayList<Node>();
		a.add(body);
		return a;
	}
	
	Symbol? lookup(string name, int pos) {
		return Symbol.lookup_in_array(parameters, name);
	}
	
	public override void print(int level) {
		print_name(level, "method");
		
		foreach (Parameter p in parameters)
			p.print(level + 1);
		if (body != null)
			body.print(level + 1);
	}
}

class Field : Variable {
	public Field(DataType type, string name, int start, int end) {
		base(type, name, start, end);
	}
	
	protected override string kind() { return "field"; }
}

// a class, struct or interface
class Class : TypeSymbol, Scope {
	public ArrayList<Symbol> members = new ArrayList<Symbol>();
	
	public Class(string name) { base(name, 0, 0); }
	
	public override ArrayList<Node>? children() { return members; }
	
	Symbol? lookup(string name, int pos) {
		return Symbol.lookup_in_array(members, name);
	}
	
	public override void print(int level) {
		print_name(level, "class");
		
		foreach (Symbol m in members)
			m.print(level + 1);
	}
}

class Enum : TypeSymbol {
	public Enum(string name, int start, int end) { base(name, start, end); }
	
	public override void print(int level) { print_name(level, "enum"); }	
}

class SourceFile : Node, Scope {
	public ArrayList<string> using_namespaces = new ArrayList<string>();
	public ArrayList<Symbol> symbols = new ArrayList<Symbol>();
	
	public override ArrayList<Node>? children() { return symbols; }

	Symbol? lookup(string name, int pos) {
		return Symbol.lookup_in_array(symbols, name);
	}

	public Symbol? resolve(string name, int pos) {
		Chain c = find(null, pos);
		return c.lookup(name, pos);
	}
	
	public override void print(int level) {
		foreach (Symbol s in symbols)
			s.print(level);
	}
}

class Parser {
	Scanner scanner;
	
	Token peek_token() { return scanner.peek_token(); }
	Token next_token() { return scanner.next_token(); }
	
	bool accept(Token t) {
		if (peek_token() == t) {
			next_token();
			return true;
		}
		return false;
	}
	
	bool skip_to(Token t) {
		while (!scanner.eof())
			if (next_token() == t)
				return true;
		return false;
	}
	
	// Skip to a right brace or semicolon.
	void skip() {
		int depth = 0;
		while (true)
			switch (next_token()) {
				case Token.EOF:
					return;
				case Token.LEFT_BRACE:
					++depth;
					break;
				case Token.RIGHT_BRACE:
					if (--depth <= 0) {
						accept(Token.SEMICOLON);
						return;
					}
					break;
				case Token.SEMICOLON:
					if (depth == 0)
						return;
					break;
			}
	}
	
	DataType? parse_type() {
		if (!accept(Token.ID))
			return null;
		DataType t = new TypeName(scanner.val());
		if (accept(Token.LESS_THAN)) {	// parameterized type
			if (parse_type() == null)
				return null;
			while (!accept(Token.GREATER_THAN)) {
				if (!accept(Token.COMMA) || parse_type() == null)
					return null;
			}
		}
		do {
			if (accept(Token.QUESTION_MARK) || accept(Token.ASTERISK))
				continue;
			if (accept(Token.LEFT_BRACKET)) {
				accept(Token.RIGHT_BRACKET);
				continue;
			}
		} while (false);
		return t;
	}
	
	Parameter? parse_parameter() {
		DataType t = parse_type();
		if (t == null || !accept(Token.ID))
			return null;
		return new Parameter(t, scanner.val(), scanner.start, scanner.end);
	}
	
	Statement? parse_statement() {
		DataType type = parse_type();
		if (type != null && accept(Token.ID)) {
			string name = scanner.val();
			int start = scanner.start;
			LocalVariable v = new LocalVariable(type, name, start, scanner.end);
			Token token = peek_token();
			if (token == Token.SEMICOLON || token == Token.EQUALS) {
				skip();
				return new DeclarationStatement(v, start, scanner.end);
			}
		}
		
		// We found no declaration.  Scan through the remainder of the
		// statement, looking for an embedded block.
		while (true)
			switch (next_token()) {
				case Token.EOF:
				case Token.RIGHT_BRACE:
				case Token.SEMICOLON:
					return null;
				case Token.LEFT_BRACE:
					return parse_block();
			}
	}

	// Parse a block after the opening brace.	
	Block? parse_block() {
		Block b = new Block();
		b.start = scanner.start;
		while (!accept(Token.RIGHT_BRACE)) {
			Statement s = parse_statement();
			if (s != null)
				b.statements.add(s);
		}
		b.end = scanner.end;
		return b;
	}
	
	Symbol? parse_method_or_field() {
		DataType type = parse_type();
		if (type == null || !accept(Token.ID)) {
			skip();
			return null;
		}
		int start = scanner.start;
		int end = scanner.end;
		string name = scanner.val();
		switch (peek_token()) {
			case Token.SEMICOLON:
			case Token.EQUALS:
				skip();
				return new Field(type, name, start, end);
			case Token.LEFT_PAREN:
				next_token();
				Method m = new Method(name);
				m.start = start;
				while (true) {
					Parameter p = parse_parameter();
					if (p == null)
						break;
					m.parameters.add(p);
					if (!accept(Token.COMMA))
						break;
				}
				if (accept(Token.RIGHT_PAREN)) {
					if (!accept(Token.SEMICOLON)) {
						if (accept(Token.LEFT_BRACE))
							m.body = parse_block();
						else skip();
					}
				} else skip();
				m.end = scanner.end;
				return m;
			default:
				skip();
				return null;
		}
	}

	bool is_modifier(Token t) {
		switch (t) {
			case Token.ABSTRACT:
			case Token.OVERRIDE:
			case Token.PRIVATE:
			case Token.PROTECTED:
			case Token.PUBLIC:
			case Token.STATIC:
			case Token.VIRTUAL:
			case Token.WEAK:
				return true;
			default:
				return false;
		}
	}

	void skip_modifiers() {
		while (is_modifier(peek_token()))
			next_token();
	}

	Symbol parse_member() {
		skip_modifiers();
		switch (peek_token()) {
			case Token.CLASS:
			case Token.INTERFACE:
			case Token.STRUCT:
				return parse_class();
			case Token.ENUM:
				return parse_enum();
			default:
				return parse_method_or_field();
		}
	}

	Class? parse_class() {
		next_token();	// move past 'class'
		if (!accept(Token.ID)) {
			skip();
			return null;
		}
		Class cl = new Class(scanner.val());
		cl.start = scanner.start;
		if (!skip_to(Token.LEFT_BRACE))
			return null;
			
		while (!scanner.eof()) {
			if (accept(Token.RIGHT_BRACE))
				break;
			Symbol m = parse_member();
			if (m != null)
				cl.members.add(m);
		}
		cl.end = scanner.end;
		return cl;
	}

	Enum? parse_enum() {
		next_token();	// move past 'enum'
		if (!accept(Token.ID)) {
			skip();
			return null;
		}
		int start = scanner.start;
		string name = scanner.val();
		skip();
		return new Enum(name, start, scanner.end);
	}

	string? parse_using() {
		if (!accept(Token.ID)) {
			skip();
			return null;
		}
		string s = scanner.val();
		skip();
		return s;
	}

	public SourceFile parse(string input) {
		scanner = new Scanner(input);
		SourceFile sf = new SourceFile();
		while (accept(Token.USING)) {
			string s = parse_using();
			if (s != null)
				sf.using_namespaces.add(s);
		}
		while (!scanner.eof()) {
			Symbol s = parse_member();
			if (s != null)
				sf.symbols.add(s);
		}
		return sf;
	}
	
	public string word_at(string input, int pos) {
		scanner = new Scanner(input);
		Token t = Token.NONE;
		while (scanner.end < pos && !scanner.eof())
			t = scanner.next_token();
		return t == Token.ID ? scanner.val() : null;
	}
}

void main(string[] args) {
    if (args.length < 2) {
        stderr.puts("usage: symbol <file>\n");
        return;
    }
    string source;
    if (!FileUtils.get_contents(args[1], out source)) {
    	stderr.puts("can't read file\n");
    	return;
    }
    SourceFile sf = new Parser().parse(source);
    sf.print(0);
}

