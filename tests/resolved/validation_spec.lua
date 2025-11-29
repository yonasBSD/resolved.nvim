local patterns = require("resolved.detection.patterns")

describe("URL validation", function()
  it("should reject URLs with path traversal attempts", function()
    local text = "See https://github.com/../../../etc/passwd/repo/issues/1"
    local results = patterns.extract_urls(text)
    assert.equals(0, #results)
  end)

  it("should reject URLs with leading dots in owner", function()
    local text = "See https://github.com/.owner/repo/issues/1"
    local results = patterns.extract_urls(text)
    assert.equals(0, #results)
  end)

  it("should reject URLs with trailing dots in repo", function()
    local text = "See https://github.com/owner/repo./issues/1"
    local results = patterns.extract_urls(text)
    assert.equals(0, #results)
  end)

  it("should reject URLs with consecutive dots", function()
    local text = "See https://github.com/owner..name/repo/issues/1"
    local results = patterns.extract_urls(text)
    assert.equals(0, #results)
  end)

  it("should accept valid URLs", function()
    local text = "See https://github.com/owner-name/repo.name/issues/123"
    local results = patterns.extract_urls(text)
    assert.equals(1, #results)
    assert.equals("owner-name", results[1].owner)
    assert.equals("repo.name", results[1].repo)
  end)
end)
