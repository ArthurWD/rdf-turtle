require 'strscan'

# Extended Bakus-Nour Form (EBNF), being the W3C variation is
# originaly defined in the
# [W3C XML 1.0 Spec](http://www.w3.org/TR/REC-xml/#sec-notation).
#
# This version attempts to be less strict than the strict definition
# to allow for coloquial variations (such as in the Turtle syntax).
#
# A rule takes the following form:
#     \[1\]  symbol ::= expression
#
# Comments include the content between '/*' and '*/'
#
# @see http://www.w3.org/2000/10/swap/grammar/ebnf2turtle.py
# @see http://www.w3.org/2000/10/swap/grammar/ebnf2bnf.n3
#
# Based on bnf2turtle by Dan Connolly.
#
# Motivation
# ----------
# 
# Many specifications include grammars that look formal but are not
# actually checked, by machine, against test data sets. Debugging the
# grammar in the XML specification has been a long, tedious manual
# process. Only when the loop is closed between a fully formal grammar
# and a large test data set can we be confident that we have an accurate
# specification of a language (and even then, only the syntax of the language).
# 
# 
# The grammar in the [N3 design note][] has evolved based on the original
# manual transcription into a python recursive-descent parser and
# subsequent development of test cases. Rather than maintain the grammar
# and the parser independently, our [goal] is to formalize the language
# syntax sufficiently to replace the manual implementation with one
# derived mechanically from the specification.
# 
# 
# [N3 design note]: http://www.w3.org/DesignIssues/Notation3
# 
# Related Work
# ------------
# 
# Sean Palmer's [n3p announcement][] demonstrated the feasibility of the
# approach, though that work did not cover some aspects of N3.
# 
# In development of the [SPARQL specification][], Eric Prud'hommeaux
# developed [Yacker][], which converts EBNF syntax to perl and C and C++
# yacc grammars. It includes an interactive facility for checking
# strings against the resulting grammars.
# Yosi Scharf used it in [cwm Release 1.1.0rc1][], which includes
# a SPAQRL parser that is *almost* completely mechanically generated.
# 
# The N3/turtle output from yacker is lower level than the EBNF notation
# from the XML specification; it has the ?, +, and * operators compiled
# down to pure context-free rules, obscuring the grammar
# structure. Since that transformation is straightforwardly expressed in
# semantic web rules (see [bnf-rules.n3][]), it seems best to keep the RDF
# expression of the grammar in terms of the higher level EBNF
# constructs.
# 
# [goal]: http://www.w3.org/2002/02/mid/1086902566.21030.1479.camel@dirk;list=public-cwm-bugs
# [n3p announcement]: http://lists.w3.org/Archives/Public/public-cwm-talk/2004OctDec/0029.html
# [Yacker]: http://www.w3.org/1999/02/26-modules/User/Yacker
# [SPARQL specification]: http://www.w3.org/TR/rdf-sparql-query/
# [Cwm Release 1.1.0rc1]: http://lists.w3.org/Archives/Public/public-cwm-announce/2005JulSep/0000.html
# [bnf-rules.n3]: http://www.w3.org/2000/10/swap/grammar/bnf-rules.n3
# 
# Open Issues and Future Work
# ---------------------------
# 
# The yacker output also has the terminals compiled to elaborate regular
# expressions. The best strategy for dealing with lexical tokens is not
# yet clear. Many tokens in SPARQL are case insensitive; this is not yet
# captured formally.
# 
# The schema for the EBNF vocabulary used here (``g:seq``, ``g:alt``, ...)
# is not yet published; it should be aligned with [swap/grammar/bnf][]
# and the [bnf2html.n3][] rules (and/or the style of linked XHTML grammar
# in the SPARQL and XML specificiations).
# 
# It would be interesting to corroborate the claim in the SPARQL spec
# that the grammar is LL(1) with a mechanical proof based on N3 rules.
# 
# [swap/grammar/bnf]: http://www.w3.org/2000/10/swap/grammar/bnf
# [bnf2html.n3]: http://www.w3.org/2000/10/swap/grammar/bnf2html.n3  
# 
# Background
# ----------
# 
# The [N3 Primer] by Tim Berners-Lee introduces RDF and the Semantic
# web using N3, a teaching and scribbling language. Turtle is a subset
# of N3 that maps directly to (and from) the standard XML syntax for
# RDF.
#
# [N3 Primer]: http://www.w3.org/2000/10/swap/Primer.html
# 
# @author Gregg Kellogg
class EBNF
  class Rule
    # Operations which are flattened to seprate rules in to_bnf
    BNF_OPS = %w{
      seq alt diff opt star plus
    }.map(&:to_sym).freeze

    # @!attribute [rw] sym for rule
    # @return [Symbol]
    attr_accessor :sym

    # @!attribute [rw] id of rule
    # @return [String]
    attr_accessor :id

    # @!attribute [rw] kind of rule
    # @return [:rule, :terminal, or :pass]
    attr_accessor :kind

    # @!attribute [rw] expr rule expression
    # @return [Array]
    attr_accessor :expr

    # @!attribute [r] orig original rule
    # @return [String]
    attr_accessor :orig

    # @param [Integer] id
    # @param [Symbol] sym
    # @param [Array] expr
    # @param [EBNF] ebnf
    # @param [Hash{Symbol => Object}] option
    # @option options [Symbol] :kind
    # @option options [String] :ebnf
    def initialize(sym, id, expr, options = {})
      @sym, @id, @expr = sym, id, expr
      @ebnf = options[:ebnf]
      @kind = case
      when options[:kind] then options[:kind]
      when sym.to_s == sym.to_s.upcase then :terminal
      when expr.is_a?(Array) && !BNF_OPS.include?(expr.first) then :terminal
      else :rule
      end
    end

    # Serializes this rule to an S-Expression
    # @return [String]
    def to_sxp
      [sym, id, kind, expr].to_sxp
    end
    def to_s; to_sxp; end
    
    # Serializes this rule to an Turtle
    # @return [String]
    def to_ttl
      @ebnf.debug("to_ttl") {inspect}
      comment = orig.strip.
        gsub(/"""/, '\"\"\"').
        gsub("\\", "\\\\").
        sub(/^\"/, '\"').
        sub(/\"$/m, '\"')
      statements = [
        %{:#{id} rdfs:label "#{id}"; rdf:value "#{sym}";},
        %{  rdfs:comment #{comment.inspect};},
      ]
      
      statements += ttl_expr(expr, kind == :terminal ? "re" : "g", 1, false)
      "\n" + statements.join("\n")
    end

    ##
    # Transform EBNF rule to BNF rules:
    #
    #   * Transform (a [n] rule (op1 (op2))) into two rules:
    #     (a [n] rule (op1 a.2))
    #     (_a_1 [n.1] rule (op2))
    #   * Transform (a rule (opt b)) into (a rule (alt g:empty "foo"))
    #   * Transform (a rule (star b)) into (a rule (alt g:empty (seq b a)))
    #   * Transform (a rule (plus b)) into (a rule (seq b (star b)
    #   * Transform (a [n] rule (op "foo")) into two rules:
    #     (a [n] rule (op _a.term1))
    #     (a.term1 [n.term1] terminal "foo")
    # @return [Array<Rule>]
    def to_bnf
      new_rules = []
      return [self] unless kind == :rule && expr.is_a?(Array)

      # Look for rules containing recursive definition and rewrite to multiple rules. If `expr` contains elements which are in array form, where the first element of that array is a symbol, create a new rule for it.
      if expr.any? {|e| e.is_a?(Array) && BNF_OPS.include?(e.first)}
        #   * Transform (a [n] rule (op1 (op2))) into two rules:
        #     (a.1 [n.1] rule (op1 a.2))
        #     (a.2 [n.2] rule (op2))
        # duplicate ourselves for rewriting
        this = dup
        rule_seq = 1
        new_rules << this

        expr.each_with_index do |e, index|
          next unless e.is_a?(Array) && e.first.is_a?(Symbol)
          new_sym, new_id = "_#{sym}_#{rule_seq}".to_sym, "#{id}.#{rule_seq}"
          rule_seq += 1
          this.expr[index] = new_sym
          new_rule = Rule.new(new_sym, new_id, e, :ebnf => @ebnf)
          new_rules << new_rule
        end

        # Return new rules after recursively applying #to_bnf
        new_rules = new_rules.map {|r| r.to_bnf}.flatten
      elsif expr.first == :opt
        #   * Transform (a rule (opt b)) into (a rule (alt g:empty "foo"))
        new_rules = Rule.new(sym, id, [:alt, :"g:empty", expr.last], :ebnf => @ebnf).to_bnf
      elsif expr.first == :star
        #   * Transform (a rule (star b)) into (a rule (alt g:empty (seq b a)))
        new_rules = [Rule.new(sym, id, [:alt, :"g:empty", "_#{sym}_star".to_sym], :ebnf => @ebnf)] +
          Rule.new("_#{sym}_star".to_sym, "#{id}*", [:seq, expr.last, sym], :ebnf => @ebnf).to_bnf
      elsif expr.first == :plus
        #   * Transform (a rule (plus b)) into (a rule (seq b (star b)
        new_rules = Rule.new(sym, id, [:seq, expr.last, [:star, expr.last]], :ebnf => @ebnf).to_bnf
      elsif expr.any? {|e| e.is_a?(String)}
        #   * Transform (a [n] rule (op "foo")) into two rules:
        #     (a [n] rule (op _a.term1))
        #     (a.term1 [n.term1] terminal "foo")
        # duplicate ourselves for rewriting
        this = dup
        rule_seq = 1
        new_rules << this

        expr.each_with_index do |e, i|
          next unless e.is_a?(String)
          new_sym, new_id = "_#{sym}_term#{rule_seq}".to_sym, "#{id}.term#{rule_seq}"
          rule_seq += 1
          this.expr[i] = new_sym
          new_rule = Rule.new(new_sym, new_id, e, :ebnf => @ebnf, :kind => :terminal)
          new_rules << new_rule
        end
      else
        # Otherwise, no further transformation necessary
        new_rules << self
      end
      
      return new_rules
    end

    def inspect
      {:sym => sym, :id => id, :kind => kind, :expr => expr}.inspect
    end

    # Two rules are equal if they have the same {#sym}, {#kind} and {#expr}
    # @param [Rule] other
    # @return [Boolean]
    def ==(other)
      sym   == other.sym &&
      kind  == other.kind &&
      expr  == other.expr
    end

    # Two rules are equivalent if they have the same {#expr}
    # @param [Rule] other
    # @return [Boolean]
    def equivalent?(other)
      expr  == other.expr
    end

    # Rewrite the rule substituting src_rule for dst_rule wherever
    # it is used in the production (first level only).
    # @param [Rule] src_rule
    # @param [Rule] dst_rule
    # @return [Rule]
    def rewrite(src_rule, dst_rule)
      case @expr
      when Array
        @expr = @expr.map {|e| e == src_rule.sym ? dst_rule.sym : e}
      else
        @expr = dst_rule.sym if @expr == src_rule.sym
      end
      self
    end

    # Rules compare using their ids
    def <=>(other)
      if id.to_i == other.id.to_i
        id <=> other.id
      else
        id.to_i <=> other.id.to_i
      end
    end

    private
    def ttl_expr(expr, pfx, depth, is_obj = true)
      indent = '  ' * depth
      @ebnf.debug("ttl_expr", :depth => depth) {expr.inspect}
      op = expr.shift if expr.is_a?(Array)
      statements = []
      
      if is_obj
        bra, ket = "[ ", " ]"
      else
        bra = ket = ''
      end

      case op
      when :seq, :alt, :diff
        statements << %{#{indent}#{bra}#{pfx}:#{op} (}
        expr.each {|a| statements += ttl_expr(a, pfx, depth + 1)}
        statements << %{#{indent} )#{ket}}
      when :opt, :plus, :star
        statements << %{#{indent}#{bra}#{pfx}:#{op} }
        statements += ttl_expr(expr.first, pfx, depth + 1)
        statements << %{#{indent} #{ket}} unless ket.empty?
      when :"'"
        statements << %{#{indent}"#{esc(expr)}"}
      when :range
        statements << %{#{indent}#{bra} re:matches #{cclass(expr.first).inspect} #{ket}}
      when :hex
        raise "didn't expect \" in expr" if expr.include?(:'"')
        statements << %{#{indent}#{bra} re:matches #{cclass(expr.first).inspect} #{ket}}
      else
        if is_obj
          statements << %{#{indent}#{expr.inspect}}
        else
          statements << %{#{indent}g:seq ( #{expr.inspect} )}
        end
      end
      
      statements.last << " ." unless is_obj
      @ebnf.debug("statements", :depth => depth) {statements.join("\n")}
      statements
    end
    
    ##
    # turn an XML BNF character class into an N3 literal for that
    # character class (less the outer quote marks)
    #
    #     >>> cclass("^<>'{}|^`")
    #     "[^<>'{}|^`]"
    #     >>> cclass("#x0300-#x036F")
    #     "[\\u0300-\\u036F]"
    #     >>> cclass("#xC0-#xD6")
    #     "[\\u00C0-\\u00D6]"
    #     >>> cclass("#x370-#x37D")
    #     "[\\u0370-\\u037D]"
    #     
    #     as in: ECHAR ::= '\' [tbnrf\"']
    #     >>> cclass("tbnrf\\\"'")
    #     'tbnrf\\\\\\"\''
    #     
    #     >>> cclass("^#x22#x5C#x0A#x0D")
    #     '^\\u0022\\\\\\u005C\\u000A\\u000D'
    def cclass(txt)
      '[' +
      txt.gsub(/\#x[0-9a-fA-F]+/) do |hx|
        hx = hx[2..-1]
        if hx.length <= 4
          "\\u#{'0' * (4 - hx.length)}#{hx}" 
        elsif hx.length <= 8
          "\\U#{'0' * (8 - hx.length)}#{hx}" 
        end
      end +
      ']'
    end
  end

  # Abstract syntax tree from parse
  attr_reader :ast

  # Parse the string or file input generating an abstract syntax tree
  # in S-Expressions (similar to SPARQL SSE)
  #
  # @param [#read, #to_s] input
  # @param [Hash{Symbol => Object}] options
  # @option options [Boolean, Array] :debug
  #   Output debug information to an array or STDOUT.
  def initialize(input, options = {})
    @options = options
    @lineno, @depth = 1, 0
    terminal = false
    @ast = []

    input = input.respond_to?(:read) ? input.read : input.to_s
    scanner = StringScanner.new(input)

    eachRule(scanner) do |r|
      debug("rule string") {r.inspect}
      case r
      when /^@terminals/
        # Switch mode to parsing terminals
        terminal = true
      when /^@pass\s*(.*)$/m
        rule = depth {ruleParts("[0] " + r)}
        rule.kind = :pass
        rule.orig = r
        @ast << rule
      else
        rule = depth {ruleParts(r)}

        rule.kind = :terminal if terminal # Override after we've parsed @terminals
        rule.orig = r
        @ast << rule
      end
    end
  end

  ##
  # Transform EBNF Rule set to BNF:
  #
  #   * Add rule [0] (g:empty rule (seq))
  #   * Transform each rule into a set of rules that are just BNF, using {Rule#to_bnf}.
  # @return [ENBF] self
  def make_bnf
    new_ast = [Rule.new(:"g:empty", "0", [:seq])]
    ast.each do |rule|
      debug("make_bnf") {"expand from: #{rule.inspect}"}
      new_rules = rule.to_bnf
      debug(" => ") {new_rules.map(&:sym).join(', ')}
      new_ast += new_rules
    end

    # Consolodate equivalent terminal rules
    to_rewrite = {}
    new_ast.select {|r| r.kind == :terminal}.each do |src_rule|
      new_ast.select {|r| r.kind == :terminal}.each do |dst_rule|
        if src_rule.equivalent?(dst_rule) && src_rule != dst_rule
          debug("make_bnf") {"equivalent rules: #{src_rule.inspect} and #{dst_rule.inspect}"}
          (to_rewrite[src_rule] ||= []) << dst_rule
        end
      end
    end

    # Replace references to equivalent rules with canonical rule
    to_rewrite.each do |src_rule, dst_rules|
      dst_rules.each do |dst_rule|
        new_ast.each do |mod_rule|
          debug("make_bnf") {"rewrite #{mod_rule.inspect} from #{dst_rule.sym} to #{src_rule.sym}"}
          mod_rule.rewrite(dst_rule, src_rule)
        end
      end
    end

    # AST now has just rewritten rules
    compacted_ast = new_ast - to_rewrite.values.flatten.compact

    # Sort AST by number
    @ast = compacted_ast.sort
    
    self
  end

  ##
  # Write out parsed syntax string as an S-Expression
  # @return [String]
  def to_sxp
    begin
      require 'sxp'
      SXP::Generator.string(ast)
    rescue LoadError
      ast.to_sxp
    end
  end
  def to_s; to_sxp; end

  def dup
    new_obj = super
    new_obj.instance_variable_set(:@ast, @ast.dup)
    new_obj
  end

  ##
  # Write out syntax tree as Turtle
  # @param [String] prefix for language
  # @param [String] ns URI for language
  # @return [String]
  def to_ttl(prefix, ns)
    unless ast.empty?
      [
        "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>.",
        "@prefix rdfs: <http://www.w3.org/2000/01/rdf-schema#>.",
        "@prefix #{prefix}: <#{ns}>.",
        "@prefix : <#{ns}>.",
        "@prefix re: <http://www.w3.org/2000/10/swap/grammar/regex#>.",
        "@prefix g: <http://www.w3.org/2000/10/swap/grammar/ebnf#>.",
        "",
        ":language rdfs:isDefinedBy <>; g:start :#{ast.first.id}.",
        "",
      ]
    end.join("\n") +

    ast.
      select {|a| [:rule, :terminal].include?(a.kind)}.
      map(&:to_ttl).
      join("\n")
  end

  ##
  # Iterate over rule strings.
  # a line that starts with '\[' or '@' starts a new rule
  #
  # @param [StringScanner] scanner
  # @yield rule_string
  # @yieldparam [String] rule_string
  def eachRule(scanner)
    cur_lineno = 1
    r = ''
    until scanner.eos?
      case
      when s = scanner.scan(%r(\s+)m)
        # Eat whitespace
        cur_lineno += s.count("\n")
        #debug("eachRule(ws)") { "[#{cur_lineno}] #{s.inspect}" }
      when s = scanner.scan(%r(/\*([^\*]|\*[^\/])*\*/)m)
        # Eat comments
        cur_lineno += s.count("\n")
        debug("eachRule(comment)") { "[#{cur_lineno}] #{s.inspect}" }
      when s = scanner.scan(%r(^@terminals))
        #debug("eachRule(@terminals)") { "[#{cur_lineno}] #{s.inspect}" }
        yield(r) unless r.empty?
        @lineno = cur_lineno
        yield(s)
        r = ''
      when s = scanner.scan(/@pass/)
        # Found rule start, if we've already collected a rule, yield it
        #debug("eachRule(@pass)") { "[#{cur_lineno}] #{s.inspect}" }
        yield r unless r.empty?
        @lineno = cur_lineno
        r = s
      when s = scanner.scan(/\[(?=\w+\])/)
        # Found rule start, if we've already collected a rule, yield it
        yield r unless r.empty?
        #debug("eachRule(rule)") { "[#{cur_lineno}] #{s.inspect}" }
        @lineno = cur_lineno
        r = s
      else
        # Collect until end of line, or start of comment
        s = scanner.scan_until(%r((?:/\*)|$)m)
        cur_lineno += s.count("\n")
        #debug("eachRule(rest)") { "[#{cur_lineno}] #{s.inspect}" }
        r += s
      end
    end
    yield r unless r.empty?
  end
  
  ##
  # Parse a rule into a rule number, a symbol and an expression
  #
  # @param [String] rule
  # @return [Rule]
  def ruleParts(rule)
    num_sym, expr = rule.split('::=', 2).map(&:strip)
    num, sym = num_sym.split(']', 2).map(&:strip)
    num = num[1..-1]
    r = Rule.new(sym && sym.to_sym, num, ebnf(expr).first, :ebnf => self)
    debug("ruleParts") { r.inspect }
    r
  end
  
  ##
  # Parse a string into an expression tree and a remaining string
  #
  # @example
  #     >>> ebnf("a b c")
  #     ((seq, \[('id', 'a'), ('id', 'b'), ('id', 'c')\]), '')
  #     
  #     >>> ebnf("a? b+ c*")
  #     ((seq, \[(opt, ('id', 'a')), (plus, ('id', 'b')), ('*', ('id', 'c'))\]), '')
  #     
  #     >>> ebnf(" | x xlist")
  #     ((alt, \[(seq, \[\]), (seq, \[('id', 'x'), ('id', 'xlist')\])\]), '')
  #     
  #     >>> ebnf("a | (b - c)")
  #     ((alt, \[('id', 'a'), (diff, \[('id', 'b'), ('id', 'c')\])\]), '')
  #     
  #     >>> ebnf("a b | c d")
  #     ((alt, \[(seq, \[('id', 'a'), ('id', 'b')\]), (seq, \[('id', 'c'), ('id', 'd')\])\]), '')
  #     
  #     >>> ebnf("a | b | c")
  #     ((alt, \[('id', 'a'), ('id', 'b'), ('id', 'c')\]), '')
  #     
  #     >>> ebnf("a) b c")
  #     (('id', 'a'), ' b c')
  #     
  #     >>> ebnf("BaseDecl? PrefixDecl*")
  #     ((seq, \[(opt, ('id', 'BaseDecl')), ('*', ('id', 'PrefixDecl'))\]), '')
  #     
  #     >>> ebnf("NCCHAR1 | diff | [0-9] | #x00B7 | [#x0300-#x036F] | \[#x203F-#x2040\]")
  #     ((alt, \[('id', 'NCCHAR1'), ("'", diff), (range, '0-9'), (hex, '#x00B7'), (range, '#x0300-#x036F'), (range, '#x203F-#x2040')\]), '')
  #     
  # @param [String] s
  # @return [Array]
  def ebnf(s)
    debug("ebnf") {"(#{s.inspect})"}
    e, s = depth {alt(s)}
    debug {"=> alt returned #{[e, s].inspect}"}
    unless s.empty?
      t, ss = depth {terminal(s)}
      debug {"=> terminal returned #{[t, ss].inspect}"}
      return [e, ss] if t.is_a?(Array) && t.first == :")"
    end
    [e, s]
  end
  
  ##
  # Parse alt
  #     >>> alt("a | b | c")
  #     ((alt, \[('id', 'a'), ('id', 'b'), ('id', 'c')\]), '')
  # @param [String] s
  # @return [Array]
  def alt(s)
    debug("alt") {"(#{s.inspect})"}
    args = []
    while !s.empty?
      e, s = depth {seq(s)}
      debug {"=> seq returned #{[e, s].inspect}"}
      if e.to_s.empty?
        break unless args.empty?
        e = [:seq, []] # empty sequence
      end
      args << e
      unless s.empty?
        t, ss = depth {terminal(s)}
        break unless t[0] == :alt
        s = ss
      end
    end
    args.length > 1 ? [args.unshift(:alt), s] : [e, s]
  end
  
  ##
  # parse seq
  #
  #     >>> seq("a b c")
  #     ((seq, \[('id', 'a'), ('id', 'b'), ('id', 'c')\]), '')
  #     
  #     >>> seq("a b? c")
  #     ((seq, \[('id', 'a'), (opt, ('id', 'b')), ('id', 'c')\]), '')
  def seq(s)
    debug("seq") {"(#{s.inspect})"}
    args = []
    while !s.empty?
      e, ss = depth {diff(s)}
      debug {"=> diff returned #{[e, ss].inspect}"}
      unless e.to_s.empty?
        args << e
        s = ss
      else
        break;
      end
    end
    if args.length > 1
      [args.unshift(:seq), s]
    elsif args.length == 1
      args + [s]
    else
      ["", s]
    end
  end
  
  ##
  # parse diff
  # 
  #     >>> diff("a - b")
  #     ((diff, \[('id', 'a'), ('id', 'b')\]), '')
  def diff(s)
    debug("diff") {"(#{s.inspect})"}
    e1, s = depth {postfix(s)}
    debug {"=> postfix returned #{[e1, s].inspect}"}
    unless e1.to_s.empty?
      unless s.empty?
        t, ss = depth {terminal(s)}
        debug {"diff #{[t, ss].inspect}"}
        if t.is_a?(Array) && t.first == :diff
          s = ss
          e2, s = primary(s)
          unless e2.to_s.empty?
            return [[:diff, e1, e2], s]
          else
            raise "Syntax Error"
          end
        end
      end
    end
    [e1, s]
  end
  
  ##
  # parse postfix
  # 
  #     >>> postfix("a b c")
  #     (('id', 'a'), ' b c')
  #     
  #     >>> postfix("a? b c")
  #     ((opt, ('id', 'a')), ' b c')
  def postfix(s)
    debug("postfix") {"(#{s.inspect})"}
    e, s = depth {primary(s)}
    debug {"=> primary returned #{[e, s].inspect}"}
    return ["", s] if e.to_s.empty?
    if !s.empty?
      t, ss = depth {terminal(s)}
      debug {"=> #{[t, ss].inspect}"}
      if t.is_a?(Array) && [:opt, :star, :plus].include?(t.first)
        return [[t.first, e], ss]
      end
    end
    [e, s]
  end

  ##
  # parse primary
  # 
  #     >>> primary("a b c")
  #     (('id', 'a'), ' b c')
  def primary(s)
    debug("primary") {"(#{s.inspect})"}
    t, s = depth {terminal(s)}
    debug {"=> terminal returned #{[t, s].inspect}"}
    if t.is_a?(Symbol) || t.is_a?(String)
      [t, s]
    elsif %w(range hex).map(&:to_sym).include?(t.first)
      [t, s]
    elsif t.first == :"("
      e, s = depth {ebnf(s)}
      debug {"=> ebnf returned #{[e, s].inspect}"}
      [e, s]
    else
      ["", s]
    end
  end
  
  ##
  # parse one terminal; return the terminal and the remaining string
  # 
  # A terminal is represented as a tuple whose 1st item gives the type;
  # some types have additional info in the tuple.
  # 
  # @example
  #     >>> terminal("'abc' def")
  #     (("'", 'abc'), ' def')
  #     
  #     >>> terminal("[0-9]")
  #     ((range, '0-9'), '')
  #     >>> terminal("#x00B7")
  #     ((hex, '#x00B7'), '')
  #     >>> terminal ("\[#x0300-#x036F\]")
  #     ((range, '#x0300-#x036F'), '')
  #     >>> terminal("\[^<>'{}|^`\]-\[#x00-#x20\]")
  #     ((range, "^<>'{}|^`"), '-\[#x00-#x20\]')
  def terminal(s)
    s = s.strip
    case m = s[0,1]
    when '"', "'"
      l, s = s[1..-1].split(m, 2)
      [l, s]
    when '['
      l, s = s[1..-1].split(']', 2)
      [[:range, l], s]
    when '#'
      s.match(/(#\w+)(.*)$/)
      l, s = $1, $2
      [[:hex, l], s]
    when /[[:alpha:]]/
      s.match(/(\w+)(.*)$/)
      l, s = $1, $2
      [l.to_sym, s]
    when '@'
      s.match(/@(#\w+)(.*)$/)
      l, s = $1, $2
      [[:"@", l], s]
    when '-'
      [[:diff], s[1..-1]]
    when '?'
      [[:opt], s[1..-1]]
    when '|'
      [[:alt], s[1..-1]]
    when '+'
      [[:plus], s[1..-1]]
    when '*'
      [[:star], s[1..-1]]
    when /[\(\)]/
      [[m.to_sym], s[1..-1]]
    else
      raise "unrecognized terminal: #{s.inspect}"
    end
  end

  def depth
    @depth += 1
    ret = yield
    @depth -= 1
    ret
  end

  ##
  # Progress output when debugging
  #
  # @overload debug(node, message)
  #   @param [String] node relative location in input
  #   @param [String] message ("")
  #
  # @overload debug(message)
  #   @param [String] message ("")
  #
  # @yieldreturn [String] added to message
  def debug(*args)
    return unless @options[:debug]
    options = args.last.is_a?(Hash) ? args.pop : {}
    depth = options[:depth] || @depth
    message = args.pop
    message = message.call if message.is_a?(Proc)
    args << message if message
    args << yield if block_given?
    message = "#{args.join(': ')}"
    str = "[#{@lineno}]#{' ' * depth}#{message}"
    @options[:debug] << str if @options[:debug].is_a?(Array)
    $stderr.puts(str) if @options[:debug] == true
  end
end
