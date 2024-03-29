-- *** UTILITY FUNCTIONS ***
local function get_locals (tab)
  local tb = {}
  for lib, keys in pairs(tab) do
    keys = string.explode(keys)
    for _, k in ipairs(keys) do
      tb[k] = _G[lib][k]
    end
  end
  return tb
end

-- str
-- string manipulation
local str = get_locals {string = "explode gsub match format lower upper"}

-- Removes space at the beginning and end and conflates multiple spaces.
function str.trim (s)
  s = str.match(s, "^%s*(.-)%s*$")
  s = str.gsub(s, "%s+", " ")
  return s
end

-- Extracts a pattern from a string, i.e. removes it and returns it.
-- If "full", then the entire pattern is removed, not only the captures.
function str.extract (s, pat, full)
  local cap = str.match(s, pat)
  if cap then
    if full then
      s = str.gsub(s, pat, "")
    else
      s = str.gsub(s, cap, "")
    end
  end
  return cap, s
end
-- /str


-- lp
-- advanced string manipulation
lpeg.locale(lpeg)
local lp = get_locals {lpeg = "match P C S Ct V alnum"}
lp.space = lpeg.space^0
-- /lp


-- tab
-- table manipulation
local tab = get_locals {table = "insert remove sort"}

-- Adds val to tab, creating it if necessary.
function tab.update (tb, val)
  tb = tb or {}
  tab.insert(tb, val)
  return tb
end

-- Adds subtable (empty, or val) to tb at entry key, unless it already exists.
function tab.subtable (tb, key, val)
  tb[key] = tb[key] or val or {}
end

-- Writes a table to an extenal file.
local function write_key (key, ind)
  return ind .. '["' .. key .. '"] = '
end

function tab.write (tb, f, ind)
  for a, b in pairs (tb) do
    if type(a) == "string" then
      a = '"' .. a .. '"'
    end
    a = "[" .. a .. "]"
    if type(b) == "table" then
      f:write(ind, a, " = {")
      tab.write(b, f, ind .. "    ")
      f:write(ind, "},")
    else
      if type(b) == "boolean" then
        b = b and "true" or "false"
      elseif type(b) == "string" then
        b = '"' .. b .. '"'
      end
      f:write(ind, a, " = ", b, ",")
    end
  end
end

-- Returns a full copy of a table. Not copying of metatables necessary for the
-- moment.
function tab.copy (tb)
  local t = {}
  for k, v in pairs (tb) do
    if type(v) == "table" then
      v = tab.copy(v)
    end
    t[k] = v
  end
  return t
end

-- Sorts two tables containing modifiers (Italic, etc.).
function tab.sortmods (a, b)
  local A, B = "", ""
  for _, x in ipairs (a) do
    A = A .. " " .. x
  end
  for _, x in ipairs (b) do
    B = B .. " " .. x
  end
  return A < B
end

-- Turns an array into a hash.
function tab.tohash(tb)
  local t = {}
  for _, k in ipairs(tb) do
    t[k] = true
  end
  return t
end
-- /tab

-- lfs
-- files etc.
local lfs = get_locals {lfs = "dir isdir isfile mkdir", kpse = "expand_var show_path find_file"}

-- Returns anything after the last dot, i.e. an extension.
function lfs.extension (s)
  return str.lower(str.match(s, "%.([^%.]*)$") or "")
--  return str.match(s, "%.([^%.]*)$") -- bugfix: dpc for empty field in file extension 230902
end

local extensions = {
  otf = "opentype",
  ttf = "truetype",
  ttc = "truetype",
}
function lfs.type (s)
  return extensions[lfs.extension(s)]
end

local kpse_extensions = {
  otf = "opentype fonts",
  ttf = "truetype fonts",
  ttc = "truetype fonts",
}
function lfs.kpse (s)
  return kpse_extensions[lfs.extension(s)]
end

-- Returns anything after the last slash, i.e. a pathless file.
function lfs.nopath (f)
  return str.match(f, "[^/]*$")
end

-- Creates a directory; the arguments are the successive subdirectories.
function lfs.ensure_dir (...)
  local arg, path = {...}
  for _, d in ipairs(arg) do
    if path then
      path = path .. "/" .. d
    else
      path = d
    end
    path = str.gsub(path, "//", "/")
    if not lfs.isdir(path) then
      lfs.mkdir(path)
    end
  end
  return path
end

-- Turns "foo/blahblah/../" into "foo/" (such going into and leaving
-- directories happens with kpse). Also puts everything to lowercase.
function lfs.smooth_file (f)
  f = str.gsub(f, "/.-/%.%./", "/")
  f = str.gsub(f, "^%a", str.lower)
  return f
end
-- /lfs


-- wri
-- messages
local wri, write_nl = {}, texio.write_nl

function wri.report (s, ...)
--	write_nl(str.format(s, unpack(arg)))
end

function wri.error (s, ...)
--  tex.error(str.format(s, unpack(arg)))
end
-- /wri


-- various
-- the last one is, of course, not the least
local io  = get_locals {io = "open lines"}
local os  = get_locals {os = "date"}
local num = get_locals {math = "abs tan rad floor pi", tex = "sp"}
local fl  = get_locals {fontloader = "open close to_table info", font = "read_tfm"}
-- /various


-- *** END OF UTILITY FUNCTIONS ***



--- *** CREATING THE LIBRARY *** ---
local settings
if lfs.find_file"blot-sets.lua" then
  settings = require"blot-sets.lua"
else
  settings = {normal = {}, features = {}}
end
local font_families = {}
local normal_names = {}
for _, name in ipairs(settings.normal) do
  normal_names[name] = true
end
local local_path   = lfs.expand_var("$TEXMFLOCAL") 
-- local local_path   = lfs.expand_var("$TEXMFHOME") -- :gsub(":",";") -- bugfix dpc: no path search gsub 0.0.2
local foundry_path = lfs.ensure_dir (local_path, "tex", "luatex", "blotfonts")
-- local foundry_path = lfs.ensure_dir (local_path, "fonts", "truetype", "public", "gfs")
local library_file = foundry_path .. "/" .. "readable.txt"
-- local library_file = "c:/texlive/texmf-local/tex/plain/pitex/readable.txt"
-- local library_file = "readable.txt"

-- Analyze a font file and return a name and a table
-- with modifiers.
local function extract_font (file, names)
  local fi, subname
  -- Trying to open a font in ttc, using the names returned by fontloader.info
  if names then
    local name = names.fullname
    if name then
      fi = fl.open (file, name)
    end
    if not fi then
      name = names.fontname
      if name then
        fi = fl.open
      end
      if not fi then
--        fl.error("Can't open %s", file)
        fl.error("\nCannot open file", file)
        return
      end
    end
    subname = name
  else
    fi = fl.open(file)
    -- blot-fonts.lua:257: attempt to index a nil value (local 'fi')
     if not fi then
        print("\nCannot open file", file)
        return
	end
  end
  -- Getting the most precise information. Not necessarily the best
  -- solution, but since the user can modify the library, it's not so bad.
  local fam, name = fi.names[1].names.preffamilyname or fi.names[1].names.family or fi.familyname, fi.fontname
  local spec = fi.names[1].names.prefmodifiers or fi.names[1].names.subfamily or ""
  local subfam, _spec
  local t = { [0]  = file }
  -- Removing mods like Regular, Book, etc.
  for name in pairs(normal_names) do
    spec = str.gsub(spec, name, "")
  end
  if subname then
    tab.insert(t, "[font = " .. subname .. "]")
  end
  if spec ~= "" then
    spec = str.explode(spec)
    for _, s in ipairs(spec) do
      tab.insert(t, s)
    end
  end
  fl.close(fi)
  return fam, t
end

-- Searches directories for font files, and pass them to
-- extract_font. The fonts are collected in a table.
-- The fonts_done table is updated when the library is read,
-- so when a font is missing and one needs to recheck files,
-- only those that arent in the libraries are considered.
local fonts_done = {}
local function check_fonts (rep, tb)
  if lfs.isdir(rep) then
  for f in lfs.dir (rep) do
    if f ~= "." and f ~= ".." then
      f = str.gsub(rep, "/$", "") .. "/" .. f
      if lfs.isdir(f) then
        check_fonts(f, tb)
      elseif lfs.isfile(f) and not fonts_done[lfs.nopath(f)] then
        local e = lfs.extension(f)
        if e == "ttf" or e == "otf" then
          local fam, file = extract_font(f)
          if fam then
            tab.subtable(tb, fam)
            tab.insert(tb[fam], file)
          end
        elseif e == "ttc" then
          local info = fl.info(f)
          for _, i in ipairs(info) do
            local fam, file = extract_font(f, i)
            if fam then
              tab.subtable(tb, fam)
              tab.insert(tb[fam], file)
            end
          end
        end
      end
    end
  end
  end
end

-- Writes the library to an external file.
-- Type is "a" if what's going on is recheck_fonts.
local function write_lib (fams, file, type)
  local read_table = {}
  for fam, tb in pairs(fams) do
    tab.insert(read_table, fam)
    for _, ttb in ipairs(tb) do
      tab.sort(ttb)
    end
    tab.sort(tb, tab.sortmods)
  end
  tab.sort(read_table)
  local readable = io.open(file, type)
  for n, fam in ipairs(read_table) do
    local log
    if type == "a" then
      log = true
      if n == 1 then
        wri.report("\nAdding new font(s):")
        readable:write("\n\n% Added automatically " .. os.date() .. "\n\n")
      end
      wri.report(fam)
    end
    readable:write(fam .. " :")
    for n, f in ipairs(fams[fam]) do
      log = log and " "
      readable:write("\n ")
      for _, t in ipairs(f) do
        log = log and log .. " " .. t
        readable:write(" " .. t)
      end
      log = log and log .. " " .. '"' .. f[0] .. '"'
      readable:write(" " .. '"' .. lfs.nopath(f[0]) .. '",')
      if log then wri.report(log) end
      if n == #fams[fam] then
        readable:write("\n\n")
      end
    end
  end
  readable:close()
end


-- If there is no library, we create it.
local font_paths = lfs.show_path("opentype fonts")
font_paths = str.gsub(font_paths, ":", ";")
font_paths = str.gsub(font_paths, "\\", "/")
font_paths = str.gsub(font_paths, "/+", "/")
font_paths = str.gsub(font_paths, "!!", "")
font_paths = str.explode(font_paths, ";+")

if not lfs.find_file(library_file) then
  wri.report("I must create the library; please wait, that can take some time.")
  for _, rep in ipairs(font_paths) do
    check_fonts(rep, font_families)
  end
  write_lib(font_families, library_file, "w")
end

-- Reads the library file, turning it into a table.
local explode_semicolon = lp.P{
  lp.Ct(lp.V"data"^1),
  data = lp.C(((1 - lp.S";[") + (lp.S"[" * (1 - lp.S"]")^0 * lp.S"]" ))^1) / str.trim * (lp.S";" + -1),
  }
local explode_comma = lp.P{
  lp.Ct(lp.V"data"^1),
  data = lp.C(((1 - lp.S",[") + (lp.S"[" * (1 - lp.S"]")^0 * lp.S"]" ))^1) / str.trim * (lp.S"," + -1),
  }

local function load_library (lib)
  local LIB  = ""
  local lib_file = lfs.find_file(lib)
  if not lib_file then
    wri.error("I can't find library %s.", lib)
    return
  end

  for l in io.lines(lib_file) do
    if not str.match(l, "^%s*%%") then
      if str.match(l, "^%s*$") then
        LIB = LIB .. ";"
      else
        LIB = LIB .. " " .. l
      end
    end
  end
  LIB = str.gsub(LIB, ";%s*;", ";;")
  LIB = str.gsub(LIB, ";+", ";")
  LIB = str.gsub(LIB, "^;", "")
  LIB = str.gsub(LIB, ":%s*:", "::")
  LIB = str.gsub(LIB, ":+", ":")
  LIB = str.gsub(LIB, "^:", "")
  LIB = str.gsub(LIB, "%s+", " ")

  LIB = lp.match(explode_semicolon, LIB)

  local newlib = {}
  for _, t in ipairs(LIB) do
    local fam, files = str.match(t, "(.-):(.*)")
    local current_mods
    if files then
      files = lp.match(explode_comma, files)
      fam = str.explode(fam, ",")
      local root
      for n, f in ipairs (fam) do
        f = str.trim(f)
        if n == 1 then
          root = f
          if type(newlib[f]) == "string" then
            wri.error("Name `%s' is already used as an alias for `%s'; it is now overwritten to denote a family", f, newlib[f])
            newlib[f] = {}
          else
            newlib[f] = newlib[f] or {}
          end
        else
          if newlib[f] then
            wri.error("The name `%s' is already used. I ignore it as an alias for `%s'", f, root)
          else
            newlib[f] = root
          end
        end
      end
      for _, f in ipairs(files) do
        local reset
        reset, f = str.extract(f, "^%.%.", true)
        if reset then current_mods = nil end
        local mods, file, feats = str.match(f, '([^"]*)"(.*)"')
        if mods then
          fonts_done[lfs.nopath(file)] = true
          feats, mods = str.extract(mods, "%[([^%]]-)]", true)
          mods = str.explode(mods)
          if current_mods then
            for _, t in ipairs(current_mods) do
              tab.insert(mods, t)
            end
            if current_mods.feats then
              feats = feats or ""
              feats = current_mods.feats .. "," .. feats
            end
          end
          local sizes, real_mods = {}, {}
          for n, s in ipairs(mods) do
            if tonumber(s) then
              tab.insert(sizes, tonumber(s))
            else
              tab.insert(real_mods, s)
            end
          end
          sizes = #sizes > 0 and sizes or {0}
          tab.sort(real_mods)
          local T = newlib[root]
          for _, t in ipairs(real_mods) do
            t = str.trim(t)
            if t ~= "" then
              T[t] = T[t] or {}
              T = T[t]
            end
          end
          T.__files = T.__files or {}
          for _, s in ipairs(sizes) do
            T.__files[s] = {str.trim(file), feats}
          end
        else
          feats, mods = str.extract(f, "%[([^%]]-)]", true)
          if current_mods then
            for _, mod in ipairs(str.explode(mods)) do
              tab.insert(current_mods, mod)
            end
            if feats then
              current_mods.feats = current_mods.feats and current_mods.feats .. "," .. feats or feats
            end
          else
            current_mods = str.explode(mods)
            current_mods.feats = feats
          end
        end
      end
    end
  end
  return newlib
end

local library = {}
library.default = load_library(library_file)

-- Same as above, but used when rechecking (if a font isn't found in libraries).
local function recheck_fonts ()
  local tb = {}
  for _, rep in ipairs(font_paths) do
    check_fonts(rep, tb)
  end
  write_lib(tb, library_file, "a")
  library.default = load_library(library_file)
end


-- This is public.
function new_library (lib)
  local l = load_library(lib)
  if l then
    tab.insert(library, l)
  end
end

--- *** END OF LIBRARY MANAGEMENT *** ---



--- *** FONT CREATION *** ---


-- Creates a new substitution for trep.
local function add_sub (f, num, sub)
  num, sub = f.map.map[num], f.map.map[sub]
  if f.glyphs[num] and f.glyphs[sub] then
    local x = f.glyphs[num]
    tab.subtable(x, "lookups")
    x.lookups.tex_trep = { { type = "substitution", specification = {variant = f.glyphs[sub].name} } }
  end
end

-- Creates a new ligature for tlig.
local function add_lig (f, lig, ...)
  lig = f.map.map[lig]
  if lig then
    arg = {...}
    local components
    for _, c in ipairs(arg) do
      c = f.map.map[c]
      c = c and f.glyphs[c]
      if c then
        c = c.name
        components = components and components .. " " .. c or c
      else
        components = nil
        break
      end
    end
    if components then
      local x = f.glyphs[lig]
      tab.subtable(x, "lookups")
      tab.subtable(x.lookups, "tex_tlig")
      tab.insert(x.lookups.tex_tlig, { type = "ligature",
        specification = {char = x.name, components = components} })
    end
  end
end

-- Loops over all the constitutents of ligatures, creating intermediary
-- ligatures if necessary. E.g. "f f i" is broken into:
-- f + f = ff.lig
-- ff.lig + i = ffi.lig
-- Then when loading the font if the intermediary ligatures do not exist
-- (e.g. "1/" in "1 / 4") a phantom character is added to the font; which might
-- be dangerous (e.g. "1/" will create a node without character if no "4" follows).
-- The ".lig" suffix is arbitrary but all glyphs marked as ligatures are also registered
-- with such a name, so if there's an "f f" ligature in a font, no matter its name, "ff.lig"
-- will point to it.
local function ligature (comp, tb, phantoms)
  if #tb == 0 then -- fast kludge to evade empty tables. jlrn 231207
    else
  local i = str.gsub(comp[1], "%.lig$", "") .. comp[2] .. ".lig"
  phantoms[i] = true
  tab.insert(tb.all_ligs, i)
  tab.subtable(tb, comp[1])
  tb[comp[1]][comp[2]] = { char = i, type = 0 } -- The type could be something else.
  tab.remove(comp, 1)
  tab.remove(comp, 1)
  if #comp > 0 then
    tab.insert(comp, 1, i)
    ligature(comp, tb, phantoms)
  end
  end -- endkludge 231209
end

local function get_lookups (t, lookup_table)
  if t then
    for _, tb in pairs(t) do
      local _tb = { tags = {} }
      if tb.features then
        for _, feats in pairs(tb.features) do
          local _tag = {}
          if feats.scripts then
            for _, scr in pairs(feats.scripts) do
              _tag[scr.script] = {}
              for _, lang in pairs(scr.langs) do
                tab.insert (_tag[scr.script], str.trim(lang))
              end
            end
          end
          for _, sub in pairs(tb.subtables) do
            tab.insert(_tb, sub.name)
          end
          _tb.tags[feats.tag] = _tag
        end
      end
      if tb.name then
        local tp = tb.type or "no_type"
        tab.subtable(lookup_table, tp)
        lookup_table[tp][tb.name] = _tb
      end
    end
  end
end

function create_font (filename, extension, path, subfont, write)

	local data = fl.open(filename, subfont)
	fontfile = fl.to_table(data)
  fl.close(data)

  local lookups = {}

	local name_touni = { }
  local max_char = 0
	for chr, gly in pairs(fontfile.map.map) do
		max_char = chr > max_char and chr or max_char
    -- Some glyphs have the same name in some fonts,
    -- e.g. the several hyphens.
    local name = fontfile.glyphs[gly].name
    while name_touni[name] do
      name = name .. "_"
    end
    name_touni[name] = chr
	end

  if fontfile.gsub then
    tab.insert(fontfile.gsub,
      { type = "gsub_single",
        name = "tex_trep",
        subtables = { {name = "tex_trep"} },
        features = { { tag = "trep"} } })
    tab.insert(fontfile.gsub,
      { type = "gsub_ligature",
        name = "tex_tlig",
        subtables = { {name = "tex_tlig"} },
        features = { { tag = "tlig"} } })
    for _, tb in ipairs(fontfile.gsub) do
      for __, ttb in ipairs(tb.subtables) do
        if tb.type == "gsub_contextchain" then
          lookups[tb.name] = lookups[tb.name] or { type = tb.type }
          tab.insert(lookups[tb.name], ttb.name)
        end
        lookups[ttb.name] = { type = tb.type }
        lookups["-" .. ttb.name] = { type = tb.type }
      end
    end
  end

  if fontfile.gpos then
    for _, tb in ipairs(fontfile.gpos) do
      for __, ttb in ipairs(tb.subtables) do
        lookups[ttb.name] = { type = tb.type }
        lookups["-" .. ttb.name] = { type = tb.type }
      end
    end
  end

  if fontfile.kerns then
    for _, class in ipairs(fontfile.kerns) do
      local max = 0
      for a in pairs (class.seconds) do
        max = max < a and a or max
      end
      if type(class.lookup) == "string" then
        lookups[class.lookup] = { type = "gpos_pair", firsts = class.firsts, seconds = class.seconds, offsets = class.offsets, max = max}
      else
        for _, lk in ipairs(class.lookup) do
          lookups[lk] = { type = "gpos_pair", firsts = class.firsts, seconds = class.seconds, offsets = class.offsets, max = max}
        end
      end
    end
  end

  add_sub(fontfile, 96, 8216) -- ` to quoteleft
  add_sub(fontfile, 39, 8217) -- ' to apostrophe (quoteright)

  add_lig(fontfile, 8220, 8216, 8216) -- quoteleft + quoteleft to quotedblleft
  add_lig(fontfile, 8221, 8217, 8217) -- quoteright + quoteright to quotedblright
  add_lig(fontfile, 8211, 45, 45)     -- -- to endash
  add_lig(fontfile, 8212, 8211, 45)   -- --- (i.e. endash + -) to emdash
  add_lig(fontfile, 161, 63, 96)      -- ?` to inverted question mark
  add_lig(fontfile, 161, 63, 8216)    -- The same, with `turned to quoteleft.
  add_lig(fontfile, 191, 33, 96)      -- !` to inverted exclamation mark
  add_lig(fontfile, 191, 33, 8216)    -- Idem.

  local characters, phantom_ligatures = {}, {}
  for chr, gly in pairs(fontfile.map.map) do
		local glyph, char = fontfile.glyphs[gly], {}

    char.index = gly
    char.name  = glyph.name
    char.width = glyph.width
    if glyph.boundingbox then
			char.depth = -glyph.boundingbox[2]
			char.height = glyph.boundingbox[4]
		end
    if glyph.italic_correction then
      char.italic = glyph.italic_correction
    elseif glyph.width and glyph.boundingbox then
      char.italic = glyph.boundingbox[3] - glyph.width
    end
    tab.subtable(characters, chr)
    characters[chr] = char

    if glyph.lookups then
      for lk, tb in pairs(glyph.lookups) do
        local _lk = "-" .. lk
        if lookups[lk] and lookups[_lk] then
          for _, l in ipairs(tb) do
            if l.type == "substitution" then

              tab.subtable(lookups[lk], "pairs")
              lookups[lk].pairs[glyph.name] = l.specification.variant

              tab.subtable(lookups[_lk], "pairs")
              lookups[_lk].pairs[l.specification.variant] = glyph.name

            elseif l.type == "ligature" then

              local comp, lig = str.explode(l.specification.components), l.specification.char
              local lig = ""
              for _, c in ipairs(comp) do
                lig = lig .. c
              end

              tab.subtable(lookups, lk)
              tab.subtable(lookups[lk], "ligs", {all_ligs = {}})
              ligature(comp, lookups[lk].ligs, phantom_ligatures)
              name_touni[lig .. ".lig"] = chr

            end
          end
        end
      end
    end

    if glyph.kerns then
			for _, kern in pairs(glyph.kerns) do
        local lks = type(kern.lookup) == "table" and kern.lookup or {kern.lookup}
        for _, lk in ipairs(lks) do
          tab.subtable(lookups[lk], "kerns")
          tab.subtable(lookups[lk].kerns, glyph.name)
          lookups[lk].kerns[glyph.name][kern.char] = kern.off
        end
			end
		end

  end

  for lig in pairs(phantom_ligatures) do
    if not name_touni[lig] then
      max_char = max_char + 1
      name_touni[lig] = max_char
      characters[max_char] = {name = lig}
    end
  end

  local lookup_table = {}
  get_lookups(fontfile.gsub, lookup_table)
	get_lookups(fontfile.gpos, lookup_table)
	get_lookups(fontfile.lookups, lookup_table, true)

  if fontfile.lookups then
    for name, lk in pairs(fontfile.lookups) do
      local tb, format = {}, lk.format
      for _, rule in ipairs(lk.rules) do
        local ttb = { lookups = rule.lookups }
        for pos, seq in pairs(rule[format]) do
          ttb[pos] = {}
          for _, glyfs in ipairs(seq) do
            glyfs = str.explode(glyfs)
            glyfs = tab.tohash(glyfs)
            tab.insert(ttb[pos], glyfs)
          end
        end
        tab.insert(tb, ttb)
      end
      lookups[name] = tb
    end
  end

	local loaded_font = {

		direction      = 0,
    filename       = filename,
		format         = extension,
		fullname       = fontfile.names[1].names.fullname,
		name           = fontfile.fontname,
		psname         = fontfile.fontname,
		type           = "real",
    units_per_em   = fontfile.units_per_em,

    auto_expand = true,

 		cidinfo = fontfile.cidinfo,

    -- Used only to adjust absoluteslant.
    italicangle         = -fontfile.italicangle,
    name_to_unicode     = name_touni,
    max_char            = max_char,
    lookups             = lookups,
    lookup_table        = lookup_table,
    characters          = characters
	}

  if write then
    local f = io.open(path, "w")
    f:write("return {")
    tab.write(loaded_font, f, "\n")
    f:write("}")
    f:close()
  end

  return loaded_font

end

-- GETTING A FONT

-- Finds a font file, and returns the original
-- file and the Lua version.
local name_luafile, get_features
local function is_font (name, mods, size)

  local lib, library_filename
  for l, t in ipairs(library) do
    if t[name] then
      library_filename = t[name]
      lib = t
      break
    end
  end
  if not library_filename then
    library_filename = library.default[name]
    lib = library.default
  end

  if library_filename then
    if type(library_filename) == "string" then
      library_filename = lib[library_filename]
    end
    tab.sort(mods)
    local T = library_filename
    for _, t in ipairs(mods) do
      local found
      for tag in pairs(T) do
        if str.match(tag, "^" .. t) then
          T = T[tag]
          found = true
          break
        end
      end
      if not found then
        T = nil
        break
      end
    end

    if T and T.__files then
      local file, feats
      local diff = 10000
      for s, f in pairs(T.__files) do
        if num.abs(s - size) < diff then
          diff = num.abs(s - size)
          file, feats = f[1], f[2]
        end
      end
      file, _file = lfs.find_file(file, lfs.kpse(file)), file
      if file then
        file = str.gsub(file, "\\", "/")
      else
        return 1, _file
      end
      local features = {}
      if feats then
        get_features(feats, features)
      end
      local lua = name_luafile(file, features.font)
      lua = lfs.isfile(lua) and lua
      return file, lua, feats
    end
  end
end

-- Returns the full path to the Lua version of the font.
-- "sub" is a font in ttc.
function name_luafile (file, sub)
  local lua
  sub = sub and "_" .. sub or ""
  sub = str.gsub(sub, " ", "_")
  if str.match(file, "/") then
    lua = str.match(file, ".*/(.-)%....$")
  else
    lua = str.match(file, "(.-)%....$")
  end
  lua = lua .. sub
  return foundry_path .. "/" .. lua .. ".lua"
end

local function apply_size (font, size, letterspacing, parameters)
  if (size < 0) then size = (- 655.36) * size end
	local to_size = size / font.units_per_em
  font.size = size
  font.designsize = size
  font.to_size = to_size
  local italic = font.italicangle or 0
  local space, stretch, shrink, extra
  if parameters == "mono" then -- Creates a monospaced font with space equal to the
                               -- width of an "m" and no stretch or shrink.
    space = font.characters[109].width * to_size
    stretch, shrink, extra = 0, 0, 0
  else
    parameters = parameters and str.explode(parameters) or {}
    space      = (parameters[1] or 0.25)     * size
    stretch    = (parameters[2] or 0.166666) * size
    shrink     = (parameters[3] or 0.111111) * size
    extra      = (parameters[4] or 0.111111) * size
  end
  font.parameters = {
      slant         = size * num.floor(num.tan(italic * num.pi/180)), -- \fontdimen 1
      space         = space,      -- \fontdimen 2
      space_stretch = stretch,    -- \fontdimen 3
      space_shrink  = shrink,     -- \fontdimen 4
      x_height      = size * 0.4, -- \fontdimen 5
      quad          = size,       -- \fontdimen 6
      extra_space   = extra       -- \fontdimen 7
    }

  letterspacing = letterspacing or 1
  for c, t in pairs(font.characters) do
    if t.width then
      t.width, t.height, t.depth = t.width * to_size * letterspacing, t.height * to_size, t.depth * to_size
      t.expansion_factor = 1000
      if t.italic then
        t.italic = t.italic * to_size
      end
    end
  end

  return font
end


local get_mods = lp.Ct((lp.space * lp.S"/" * lp.C(lp.alnum^1))^0)
local get_feats = lp.Ct((lp.C((1 - lp.S",;")^1) * (lp.S",;" + -1))^1)
function get_features (features, tb)
  features = lp.match(get_feats, features) or {}
  for _, f in ipairs(features) do
    if str.match(f, "=") then
      local key, val = str.match(f, "%s*(.-)%s*=%s*(.*)")
      val = str.trim(val)
      if val == "false" then
        tb[key] = nil
      else
        tb[key] = val
      end
    else
      f = str.trim(f)
      neg, f = str.extract(f, "^%-")
      if neg then
        tb[f] = nil
      else
        _, f = str.extract(f, "^%+")
        tb[f] = true
      end
    end
  end
end

local lookup_functions = {}

function lookup_functions.gsub_single (tb, f)
  local name_touni = f.name_to_unicode
  for a, b in pairs(tb.pairs) do
    local _a, _b = name_touni[a], name_touni[b]
    f.max_char = f.max_char + 1
    f.characters[f.max_char] = f.characters[_a]
    f.characters[_a] = f.characters[_b]
    name_touni[a], name_touni[b] = f.max_char, _a
  end
  return f
end

function lookup_functions.gsub_ligature (tb, f)
  local name_touni = f.name_to_unicode
  tb.ligs.all_ligs = nil
  for a, tb in pairs(tb.ligs) do
    a = name_touni[a]
    tab.subtable(f.characters[a], "ligatures")
    for b, ttb in pairs(tb) do
      b, c = name_touni[b], name_touni[ttb.char]
      f.characters[a].ligatures[b] = {char = c, type = ttb.type}
    end
  end
  return f
end

local function kern_pairs (tb, firsts, seconds, offset)
  for _, c1 in ipairs(str.explode(firsts)) do
    for __, c2 in ipairs(str.explode(seconds)) do
      tab.subtable(tb, c1)
      tb[c1][c2] = offset
    end
  end
end

local function kern_classes (firsts, seconds, offsets, max)
  local kerns = {}
  for f, F in pairs (firsts) do
    for s, S in pairs (seconds) do
      local off = offsets[(f-1) * max + s]
      if off then
        kern_pairs (kerns, F, S, off)
      end
    end
  end
  return kerns
end

local function apply_kerns (f, kerns, to_size)
  local name_touni = f.name_to_unicode
  to_size = to_size or 1
  for c1, ttb in pairs(kerns) do
    for c2, off in pairs(ttb) do
      tab.subtable(f.characters[name_touni[c1]], "kerns")
      f.characters[name_touni[c1]].kerns[name_touni[c2]] = off * to_size
    end
  end
end

function lookup_functions.gpos_pair (tb, f)
  -- These are the big kern classes.
  if tb.offsets then
    local name_touni = f.name_to_unicode
    for n, off in pairs(tb.offsets) do
      tb.offsets[n] = off * f.to_size
    end
    local kerns = kern_classes(tb.firsts, tb.seconds, tb.offsets, tb.max)
    apply_kerns(f, kerns)
  end
  -- These are the ones retrieved from individual glyphs.
  if tb.kerns then
    apply_kerns(f, tb.kerns, f.to_size)
  end
  return f
end

function lookup_functions.gsub_contextchain (tb, f)
  local name_touni = f.name_to_unicode
  local T = f.contextchain or {}
  for _, llk in ipairs(tb) do
    if fontfile.lookups then
      local sub, Sub = fontfile.lookups[llk].rules[1].lookups
      local chain = fontfile.lookups[llk].rules[1].coverage
      local cur, current = str.explode(chain.current[1]), {}
      local aft, after = chain.after and str.explode(chain.after[1]) or {}, {}
      for _, c in ipairs(cur) do
        c = name_touni[c]
        if sub then
          Sub = {}
          for n, x in ipairs(sub) do
            Sub[n] = name_touni[fontfile.glyphs[f.characters[c].index].lookups[x .. "_s"][1].specification.variant]
          end
        end
        local t = { lookup = Sub}
        tab.subtable(T, C)
        for __, a in ipairs(aft) do
          tab.subtable(t, "after")
          t.after[name_touni[a]] = true
        end
        tab.insert(T[c], t)
      end
    end
  end
  f.contextchain = T
  return f
end

local function _isactive (tb, ft, sc, lg)
  for t in pairs(tb.tags) do
    if ft[t] then
      if t[sc] then
        for _, lang in pairs(tb[sc]) do
          if lang == lg then
            return true
          end
        end
      else
        return true
      end
    end
  end
end


local lookup_types = {
  "gsub_single",
  "gsub_ligature",
  "gpos_pair"
  }

local function activate_lookups (font, features, script, lang)
  for _, type in ipairs(lookup_types) do
    if font.lookup_table and font.lookup_table[type] then
      for l, tb in pairs(font.lookup_table[type]) do
        if _isactive(tb, features, script, lang) then
          for _, lk in ipairs(tb) do
            local lt = font.lookups[lk]
            if lt then
              font = lookup_functions[type](lt, font)
            end
          end
        end
      end
    end
  end
  return font
end

local function load_font (name, size, id, done)
  local loaded_font = lfs.find_file(name, "tfm")
  if loaded_font then
    loaded_font = fl.read_tfm(loaded_font, size)
  else
    local original = str.trim(str.match(name, "[^:]*"))
    local family, mods, feats
    family, name = str.extract(name, "([^/:]*)")
    family = str.trim(family)
    mods, name = str.extract(name, "[^:]*")
    mods = lp.match(get_mods, mods) or {}
    feats = str.extract(name, ":(.*)") or ""
    local features = tab.copy(settings.features)
    get_features(feats, features)

    local at_size
    if features.size then
      at_size = features.size
    else
      at_size = size
      at_size = at_size > 0 and at_size or at_size * - 655.36
      at_size = at_size / 65536
    end
    local source, lua, add_feats = is_font(family, mods, at_size)
    if add_feats then get_features(add_feats, features) end

    if type(source) == "string" then
      local cache = features.cache or "yes"
      if lua then
        if cache == "no" or cache == "rewrite" then
          loaded_font = create_font(source, lfs.type(source), lua, features.font, cache == "rewrite")
        else
          loaded_font = dofile(lua)
        end
      else
        lua = name_luafile(source, features.font)
        loaded_font = create_font(source, lfs.type(source), lua, features.font, cache ~= "no")
      end
    else
      if not done then
        if type(source) == "number" then
          wri.error("The library says `%s' matches `%s', but I can't find that file anywhere. Clean up your library!", original, lua)
        else
          recheck_fonts()
          return load_font(original, size, id, true)
        end
      else
        wri.error("I can't find `%s'. I return a default font to avoid further errors.", original)
      end
    end

    if loaded_font then

      local expansion = features.expansion and str.explode(features.expansion) or {}
      loaded_font.stretch = expansion[1] or 0
      loaded_font.shrink  = expansion[2] or 0
      loaded_font.step    = expansion[3] or 0

      local extend = features.extend or 1
      loaded_font.extend  = extend * 1000
      local slant
      if features.absoluteslant then
        local italic = loaded_font.italicangle or 0
        slant = features.absoluteslant - italic
      else
        slant = features.slant or 0
      end
      loaded_font.slant   = num.tan(num.rad(slant)) * 1000

      loaded_font = apply_size(loaded_font, size, features.letterspacing, features.space)
      loaded_font = activate_lookups(loaded_font, features, features.script, features.lang)

      if #loaded_font == 0 then  -- kludge for missing families/series, etc. 231207. jlrn.
        else -- kludge 231207
      loaded_font.name = loaded_font.name .. id
      loaded_font.fullname = loaded_font.fullname .. id 
      local embedding = features.embedding or "subset"
      if embedding ~= "no" and embedding ~= "subset" and embedding ~= "full" then
        wri.error("Invalid value `%s' for the `embedding' feature. Value should be `no', `subset' or `full'.", embedding)
        embedding = "subset"
      end
      loaded_font.embedding = embedding
      end -- endkludge 231207
    else
      loaded_font = fl.read_tfm(lfs.find_file("cmr10", "tfm"), size)
    end
  end
  return loaded_font
end

callback.register("define_font", load_font)

--[[
History
0.0.0 First release
0.0.1 Bugfix
0.0.2 2023-06-28 Bugfix on font path search: removed gsubs for Nix&Win
0.0.3 2023-09-02 Bugfix on font path search: empty file extensions in font paths
0.0.4 2023-12-07 Two kludges: one for missing ligatures, another for missing families/series; 
      some cleanup and housekeeping.
--]]