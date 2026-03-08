local M = {}

---@param framework string
---@param test_name string
---@param namespace string
---@param class_name string
---@return string
function M.build_new_test_file(framework, test_name, namespace, class_name)
  local attribute, using
  if framework == "nunit" then
    attribute = "[Test]"
    using = "using NUnit.Framework;"
  elseif framework == "mstest" then
    attribute = "[TestMethod]"
    using = "using Microsoft.VisualStudio.TestTools.UnitTesting;"
  else
    attribute = "[Fact]"
    using = "using Xunit;"
  end

  return string.format([[%s

namespace %s;

public class %sTests
{
    %s
    public void %s()
    {
        // Arrange

        // Act

        // Assert
        throw new NotImplementedException();
    }
}
]], using, namespace, class_name, attribute, test_name)
end

---@param framework string
---@param test_name string
---@return string
function M.build_test_method_stub(framework, test_name)
  local attribute
  if framework == "nunit" then
    attribute = "[Test]"
  elseif framework == "mstest" then
    attribute = "[TestMethod]"
  else
    attribute = "[Fact]"
  end

  return string.format([[
    %s
    public void %s()
    {
        // Arrange

        // Act

        // Assert
        throw new NotImplementedException();
    }
]], attribute, test_name)
end

return M
