-- Link inline R code, such as `sum()` or `project()`, to documentation.
-- Quarto's code-link option handles code blocks; downlit can resolve the
-- matching URLs for inline code too.

local urls = {}

local function is_html_output()
  return FORMAT:match("html") ~= nil
end

local function code_candidates(doc)
  local seen = {}
  local codes = {}

  doc:walk({
    Code = function(el)
      local text = el.text
      if text ~= nil and text ~= "" and string.len(text) < 200 and not seen[text] then
        seen[text] = true
        table.insert(codes, text)
      end
    end
  })

  return codes
end

local function downlit_urls(codes)
  if #codes == 0 then
    return {}
  end

  local r_code = [[
suppressPackageStartupMessages(library(downlit))
options(downlit.attached = c(
  "mizer", "stats", "graphics", "grDevices", "utils",
  "datasets", "methods", "base"
))
codes <- readLines("stdin", warn = FALSE)
urls <- vapply(codes, function(code) {
  url <- downlit::autolink_url(code)
  if (length(url) == 0 || is.na(url)) "" else url
}, character(1), USE.NAMES = FALSE)
writeLines(urls)
]]

  local ok, output = pcall(
    pandoc.pipe,
    "Rscript",
    {"--vanilla", "-e", r_code},
    table.concat(codes, "\n")
  )

  local results = {}

  if not ok then
    io.stderr:write("inline-code-links.lua: downlit URL lookup failed; leaving inline code unlinked.\n")
    return results
  end

  local i = 1
  for line in (output .. "\n"):gmatch("([^\n]*)\n") do
    if line ~= "" then
      results[codes[i]] = line
    end
    i = i + 1
  end

  return results
end

function Pandoc(doc)
  if not is_html_output() then
    return doc
  end

  urls = downlit_urls(code_candidates(doc))

  return doc:walk({
    Code = function(el)
      local url = urls[el.text]
      if url ~= nil then
        return pandoc.Link({el}, url)
      end
      return nil
    end
  })
end
