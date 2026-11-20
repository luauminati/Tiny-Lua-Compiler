local tlc = require("tlc")

return function(suite)
  suite:describe("Parser", function()
    suite:it("builds precedence trees for arithmetic expressions", function()
      local ast = tlc.parse("return 1 + 2 * 3")
      local expression = ast.body.statements[1].expressions[1]

      suite:assertMatchesShape({
        kind = "BinaryOperator",
        operator = "+",
        left = { kind = "NumericLiteral", value = 1 },
        right = {
          kind = "BinaryOperator",
          operator = "*",
          left = { kind = "NumericLiteral", value = 2 },
          right = { kind = "NumericLiteral", value = 3 },
        },
      }, expression)
    end)

    suite:it("keeps power operator right-associative in the AST", function()
      local ast = tlc.parse("return 2 ^ 3 ^ 2")
      local expression = ast.body.statements[1].expressions[1]

      suite:assertMatchesShape({
        kind = "BinaryOperator",
        operator = "^",
        left = { kind = "NumericLiteral", value = 2 },
        right = {
          kind = "BinaryOperator",
          operator = "^",
          left = { kind = "NumericLiteral", value = 3 },
          right = { kind = "NumericLiteral", value = 2 },
        },
      }, expression)
    end)

    suite:it("preserves parenthesized function calls as AST nodes", function()
      local ast = tlc.parse("return (f())")
      local expression = ast.body.statements[1].expressions[1]

      suite:assertMatchesShape({
        kind = "ParenthesizedExpression",
        expression = {
          kind = "FunctionCall",
          callee = { kind = "Identifier", value = "f" },
          arguments = {},
          isMethodCall = false,
        },
      }, expression)
    end)

    suite:it("parses local function declarations as dedicated nodes", function()
      local ast = tlc.parse("local function f(a, ...) return a end")
      local node = ast.body.statements[1]

      suite:assertMatchesShape({
        kind = "LocalFunctionDeclaration",
        name = "f",
        body = {
          kind = "FunctionExpression",
          parameters = { "a" },
          isVararg = true,
        },
      }, node)
    end)

    suite:it(
      "desugars method declarations into assignments with self",
      function()
        local ast = tlc.parse("function t:m(a) return a end")
        local node = ast.body.statements[1]

        suite:assertMatchesShape({
          kind = "AssignmentStatement",
          lvalues = {
            {
              kind = "IndexExpression",
              base = { kind = "Identifier", value = "t" },
              index = { kind = "StringLiteral", value = "m" },
            },
          },
          expressions = {
            {
              kind = "FunctionExpression",
              parameters = { "self", "a" },
              isVararg = false,
            },
          },
        }, node)
      end
    )

    suite:it("marks method calls distinctly from normal calls", function()
      local ast = tlc.parse("return obj:method(1)")
      local expression = ast.body.statements[1].expressions[1]

      suite:assertMatchesShape({
        kind = "FunctionCall",
        isMethodCall = true,
        callee = {
          kind = "IndexExpression",
          base = { kind = "Identifier", value = "obj" },
          index = { kind = "StringLiteral", value = "method" },
        },
        arguments = { { kind = "NumericLiteral", value = 1 } },
      }, expression)
    end)

    suite:it(
      "parses table constructor sugar into explicit element nodes",
      function()
        local ast = tlc.parse("return {x = 1, [2] = 3, 4}")
        local expression = ast.body.statements[1].expressions[1]

        suite:assertMatchesShape({
          kind = "TableConstructor",
          elements = {
            {
              kind = "TableElement",
              isImplicit = false,
              key = { kind = "StringLiteral", value = "x" },
              value = { kind = "NumericLiteral", value = 1 },
            },
            {
              kind = "TableElement",
              isImplicit = false,
              key = { kind = "NumericLiteral", value = 2 },
              value = { kind = "NumericLiteral", value = 3 },
            },
            {
              kind = "TableElement",
              isImplicit = true,
              key = { kind = "NumericLiteral", value = 1 },
              value = { kind = "NumericLiteral", value = 4 },
            },
          },
        }, expression)
      end
    )

    suite:it("parses local declarations without initializers", function()
      local ast = tlc.parse("local a, b")
      local node = ast.body.statements[1]

      suite:assertMatchesShape({
        kind = "LocalDeclarationStatement",
        variables = { "a", "b" },
        initializers = {},
      }, node)
    end)

    suite:it("parses implicit string and table call syntax", function()
      local stringCall = tlc.parse([[return print "hello"]])
      local tableCall = tlc.parse([[return f {1, 2}]])

      suite:assertMatchesShape({
        kind = "FunctionCall",
        callee = { kind = "Identifier", value = "print" },
        arguments = { { kind = "StringLiteral", value = "hello" } },
        isMethodCall = false,
      }, stringCall.body.statements[1].expressions[1])

      suite:assertMatchesShape({
        kind = "FunctionCall",
        callee = { kind = "Identifier", value = "f" },
        arguments = { { kind = "TableConstructor" } },
        isMethodCall = false,
      }, tableCall.body.statements[1].expressions[1])
    end)

    suite:it("parses chained call and index suffixes", function()
      local ast = tlc.parse([=[return t:f().g["x"]]=])

      suite:assertMatchesShape({
        kind = "IndexExpression",
        base = {
          kind = "IndexExpression",
          base = {
            kind = "FunctionCall",
            isMethodCall = true,
          },
          index = { kind = "StringLiteral", value = "g" },
        },
        index = { kind = "StringLiteral", value = "x" },
      }, ast.body.statements[1].expressions[1])
    end)

    suite:it("distinguishes numeric and generic for loops", function()
      local numericAst = tlc.parse("for i = 1, 3 do return i end")
      local genericAst = tlc.parse("for k, v in pairs(t) do return v end")

      suite:assertEqual(
        "ForNumericStatement",
        numericAst.body.statements[1].kind
      )
      suite:assertEqual(
        "ForGenericStatement",
        genericAst.body.statements[1].kind
      )
      suite:assertDeepEqual(
        { "k", "v" },
        genericAst.body.statements[1].iterators
      )
    end)

    suite:it(
      "parses call statements without turning them into assignments",
      function()
        local ast = tlc.parse("print(1)")
        local node = ast.body.statements[1]

        suite:assertMatchesShape({
          kind = "CallStatement",
          expression = {
            kind = "FunctionCall",
            callee = { kind = "Identifier", value = "print" },
          },
        }, node)
      end
    )

    suite:it("parses goto statements and labels", function()
      local ast = tlc.parse("for i = 1, 2 do goto continue; ::continue:: end")
      local statements = ast.body.statements[1].body.statements

      suite:assertMatchesShape({
        kind = "GotoStatement",
        label = "continue",
      }, statements[1])

      suite:assertMatchesShape({
        kind = "LabelStatement",
        label = "continue",
      }, statements[2])
    end)

    suite:it("keeps a label separate from the identifier before it", function()
      local ast = tlc.parse([[
        do
          s = s + n
          ::continue::
        end
      ]])
      local statements = ast.body.statements[1].body.statements

      suite:assertEqual("AssignmentStatement", statements[1].kind)
      suite:assertMatchesShape({
        kind = "LabelStatement",
        label = "continue",
      }, statements[2])
    end)

    suite:it("errors on invalid statement starters", function()
      suite:assertError(function()
        tlc.parse("f() = 1")
      end, "Invalid statement")
    end)

    suite:it("errors on trailing parameter commas", function()
      suite:assertError(function()
        tlc.parse("function f(a, b,) end")
      end, "Expected parameter name or '%.%.%.'")
    end)

    suite:it("errors on numeric for loops missing a limit", function()
      suite:assertError(function()
        tlc.parse("for i = 1 do return i end")
      end, "requires at least a start and limit expression")
    end)

    suite:it("errors on numeric for loops with too many expressions", function()
      suite:assertError(function()
        tlc.parse("for i = 1, 2, 3, 4 do return i end")
      end, "allows at most a start, limit, and optional step expression")
    end)
  end)
end
