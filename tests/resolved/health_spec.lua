describe("health checks", function()
  it("should load health module", function()
    assert.has_no.errors(function()
      require("resolved.health")
    end)
  end)

  it("should have check function", function()
    local health = require("resolved.health")
    assert.is_function(health.check)
  end)

  -- Note: Actually running health.check() would require mocking
  -- the vim.health API which is complex. These basic tests
  -- verify the module structure is correct.
end)
