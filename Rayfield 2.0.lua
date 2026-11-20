local function getService(name)
	local service = game:GetService(name)
	return if cloneref then cloneref(service) else service
end

-- Services
local UserInputService = getService("UserInputService")
local TweenService = getService("TweenService")
local Players = getService("Players")
local CoreGui = getService("CoreGui")

local toggleKeybind = "K"

local RAYVOID_BASE      = "RAYVOID"
local ConfigurationExtension = ".rfld"
local VoidPrefsFile     = RAYVOID_BASE .. "/RayVoid.json"
local CPlaceFolder      = nil   -- "RAYVOID/{PlaceId}"
local CAutoloadFile     = nil   -- "RAYVOID/{PlaceId}/autoload.json"
local CActiveSlot       = nil   -- nom du slot actif (string, sans extension)
local CEnabled          = false -- ConfigurationSaving.Enabled
local CAutoLoadSlot     = nil   -- slot à charger au lancement (nil = désactivé)
local _hasFS            = false -- true si l'executor supporte le filesystem
local _pendingTheme     = nil   -- thème lu dans VoidPrefs, appliqué après construction UI
local _currentThemeName = "Default" -- nom du thème actif, mis à jour par ChangeTheme
local _suppressNotify   = false -- true pendant la restauration d'une config : avale les notifs des callbacks
local _mainTabEnabled   = false -- true si Ui:MainCredit() a été appelé (crée l'onglet Main en 1er)
local _mainTabOpts      = nil   -- config optionnelle passée à MainCredit()

local VC = {
    BgDeep      = Color3.fromRGB(8,   8,  12),
    BgMid       = Color3.fromRGB(14,  14, 20),
    BgLight     = Color3.fromRGB(22,  22, 32),
    BgLighter   = Color3.fromRGB(30,  28, 45),
    Accent      = Color3.fromRGB(130, 80,  255),
    AccentSoft  = Color3.fromRGB(100, 60,  200),
    AccentPink  = Color3.fromRGB(220, 80,  160),
    AccentGlow  = Color3.fromRGB(160, 110, 255),
    TextBright  = Color3.fromRGB(240, 238, 255),
    TextMid     = Color3.fromRGB(160, 155, 190),
    TextDim     = Color3.fromRGB(85,  82,  115),
    BorderDim   = Color3.fromRGB(35,  32,  58),
    Success     = Color3.fromRGB(55,  210, 120),
    Warning     = Color3.fromRGB(255, 185, 40),
    Error       = Color3.fromRGB(230, 55,  75),
    Info        = Color3.fromRGB(60,  155, 255),
    White       = Color3.fromRGB(255, 255, 255),
    Black       = Color3.fromRGB(0,   0,   0),
}

-- Tween simplifié VoidUI
local function VTween(obj, props, duration, style, direction)
    duration  = duration  or 0.15
    style     = style     or Enum.EasingStyle.Quint
    direction = direction or Enum.EasingDirection.Out
    TweenService:Create(obj, TweenInfo.new(duration, style, direction), props):Play()
end

-- UICorner
local function VCorner(radius, parent)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 6)
    c.Parent = parent
    return c
end

-- UIStroke
local function VStroke(thickness, color, parent, transparency)
    local s = Instance.new("UIStroke")
    s.Thickness       = thickness    or 1
    s.Color           = color        or VC.BorderDim
    s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    s.Transparency    = transparency or 0
    s.Parent          = parent
    return s
end

-- UIPadding
local function VPad(top, bottom, left, right, parent)
    local p = Instance.new("UIPadding")
    p.PaddingTop    = UDim.new(0, top    or 0)
    p.PaddingBottom = UDim.new(0, bottom or 0)
    p.PaddingLeft   = UDim.new(0, left   or 0)
    p.PaddingRight  = UDim.new(0, right  or 0)
    p.Parent = parent
    return p
end

-- UIGradient
local function VGradient(color0, color1, parent, rotation)
    local g = Instance.new("UIGradient")
    g.Color    = ColorSequence.new(color0, color1)
    g.Rotation = rotation or 0
    g.Parent   = parent
    return g
end

-- Frame basique
local function VMakeFrame(parent, size, position, bgColor, bgTransparency)
    local f = Instance.new("Frame")
    f.Size                   = size           or UDim2.new(1, 0, 1, 0)
    f.Position               = position       or UDim2.new(0, 0, 0, 0)
    f.BackgroundColor3       = bgColor        or VC.BgMid
    f.BackgroundTransparency = bgTransparency or 0
    f.BorderSizePixel        = 0
    f.Parent                 = parent
    return f
end

-- TextLabel basique
local function VMakeLabel(parent, text, size, position, textColor, textSize, font, xAlign)
    local l = Instance.new("TextLabel")
    l.Size                   = size      or UDim2.new(1, 0, 1, 0)
    l.Position               = position  or UDim2.new(0, 0, 0, 0)
    l.BackgroundTransparency = 1
    l.Text                   = text      or ""
    l.TextColor3             = textColor or VC.TextBright
    l.TextSize               = textSize  or 13
    l.Font                   = font      or Enum.Font.GothamBold
    l.TextXAlignment         = xAlign    or Enum.TextXAlignment.Left
    l.BorderSizePixel        = 0
    l.Parent                 = parent
    return l
end

-- Barre d'accent gauche dégradée (déco sur chaque composant)
local function VMakeAccentBar(parent)
    local bar = VMakeFrame(parent,
        UDim2.new(0, 3, 0.55, 0),
        UDim2.new(0, 0, 0.225, 0),
        VC.White, 0
    )
    VCorner(2, bar)
    VGradient(VC.Accent, VC.AccentPink, bar, 90)
    return bar
end


-- Loads and executes a function hosted on a remote URL. Cancels the request if the requested URL takes too long to respond.
-- Errors with the function are caught and logged to the output
local function loadWithTimeout(url: string, timeout: number?): ...any
	assert(type(url) == "string", "Expected string, got " .. type(url))
	timeout = timeout or 5
	local requestCompleted = false
	local success, result = false, nil

	local requestThread = task.spawn(function()
		local fetchSuccess, fetchResult = pcall(game.HttpGet, game, url) -- game:HttpGet(url)
		-- If the request fails the content can be empty, even if fetchSuccess is true
		if not fetchSuccess or #fetchResult == 0 then
			if #fetchResult == 0 then
				fetchResult = "Empty response" -- Set the error message
			end
			success, result = false, fetchResult
			requestCompleted = true
			return
		end
		local content = fetchResult -- Fetched content
		local execSuccess, execResult = pcall(function()
			return loadstring(content)()
		end)
		success, result = execSuccess, execResult
		requestCompleted = true
	end)

	local timeoutThread = task.delay(timeout, function()
		if not requestCompleted then
			warn("Request for " .. url .. " timed out after " .. tostring(timeout) .. " seconds")
			task.cancel(requestThread)
			result = "Request timed out"
			requestCompleted = true
		end
	end)

	-- Wait for completion or timeout
	while not requestCompleted do
		task.wait()
	end
	-- Cancel timeout thread if still running when request completes
	if coroutine.status(timeoutThread) ~= "dead" then
		task.cancel(timeoutThread)
	end
	if not success then
		warn("Failed to process " .. tostring(url) .. ": " .. tostring(result))
	end
	return if success then result else nil
end

local _getgenv = rawget(_G, "getgenv")
local customAssetId = nil
local secureMode = false
if _getgenv then
	local ok2, result2 = pcall(function() return _getgenv().RAYFIELD_ASSET_ID end)
	if ok2 and type(result2) == "number" then customAssetId = result2 end
	local ok3, result3 = pcall(function() return _getgenv().RAYFIELD_SECURE end)
	if ok3 and result3 then secureMode = true end
end

if secureMode then
	local _error = error
	local _assert = assert
	warn = function(...) end
	print = function(...) end
	error = function(_, level) _error("", level) end
	assert = function(v, ...) return _assert(v) end
end

local secureWarnings = {}
local customAssets = {}

local function secureNotify(wType, title, content)
	if secureWarnings[wType] then return end
	secureWarnings[wType] = true
	task.spawn(function()
		while not RayfieldLibrary or not RayfieldLibrary.Notify do task.wait(0.5) end
		RayfieldLibrary:Notify({
			Title = title,
			Content = content,
			Duration = 8,
		})
	end)
end
local InterfaceBuild = 'UU2NX'
local Release = "Build 1.746"
local RayfieldFolder = "Rayfield"
-- RAYVOID_BASE, ConfigurationExtension, VoidPrefsFile, CPlaceFolder, CAutoloadFile
-- déclarés en haut du fichier (avant les fonctions qui les utilisent)



local HttpService = getService('HttpService')
local RunService = getService('RunService')

-- Environment Check
local useStudio = RunService:IsStudio() or false

local requestFunc = (syn and syn.request) or (fluxus and fluxus.request) or (http and http.request) or http_request or request



-- The function below provides a safe alternative for calling error-prone functions
-- Especially useful for filesystem function (writefile, makefolder, etc.)
local function callSafely(func, ...)
	if func then
		local success, result = pcall(func, ...)
		if not success then
			warn("Rayfield | Function failed with error: ", result)
			return false
		else
			return result
		end
	end
end

-- Vérifie si un dossier existe — compatible YuBX (isfolder peut ne pas exister)
local function _isfolder(path)
	if type(isfolder) == "function" then
		local ok, result = pcall(isfolder, path)
		return ok and result == true
	end
	-- Fallback : on tente de lister — si ça ne plante pas, le dossier existe
	if type(listfiles) == "function" then
		local ok = pcall(listfiles, path)
		return ok
	end
	return false
end

-- Ensures a folder exists by creating it if needed
local function ensureFolder(folderPath)
	if not _isfolder(folderPath) then
		pcall(makefolder, folderPath)
	end
end

local ChangeTheme -- forward declaration (définie plus bas)

-- ════════════════════════════════════════════════════════════════════════════
--  RAYVOID PREFS — fichier global RayVoid_cfg/RayVoid.json
--  Stocke : thème actif, touche hide/show
--  Chargé au démarrage, sauvegardé à chaque changement
-- ════════════════════════════════════════════════════════════════════════════
local function _saveVoidPrefs()
	local canWrite = _hasFS or (type(makefolder) == "function" and type(writefile) == "function")
	if not canWrite then warn("[RV] _saveVoidPrefs : pas de filesystem") return end
	if not _isfolder(RAYVOID_BASE) then
		local ok, err = pcall(makefolder, RAYVOID_BASE)
	end
	local ok, err = pcall(writefile, VoidPrefsFile, HttpService:JSONEncode({
		theme   = _currentThemeName,
		keybind = toggleKeybind,
	}))
end

local function _loadVoidPrefs()
	local canRead = _hasFS or (type(isfile) == "function" and type(readfile) == "function")
	if not canRead then return end
	local exists = isfile(VoidPrefsFile)
	if not exists then return end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(VoidPrefsFile))
	end)
	if not ok or type(data) ~= "table" then return end
	if type(data.keybind) == "string" and data.keybind ~= "" then
		toggleKeybind = data.keybind
	end
	if type(data.theme) == "string" and data.theme ~= "" then
		-- On stocke sans vérifier RayfieldLibrary.Theme (pas encore disponible ici)
		-- La vérification se fait dans le watcher UI ready
		_pendingTheme = data.theme
	end
end





-- ════════════════════════════════════════════════════════════════════════════
--  MULTI-CONFIG HELPERS
-- ════════════════════════════════════════════════════════════════════════════

-- Liste les noms de configs disponibles dans CPlaceFolder (sans extension)
local function _listConfigs()
	if not CPlaceFolder then return {} end
	if not (listfiles) then return {} end
	if not _isfolder(CPlaceFolder) then return {} end
	local result = {}
	local ok, files = pcall(listfiles, CPlaceFolder)
	if not ok then return {} end
	for _, f in ipairs(files) do
		-- Compatibilité slash / backslash entre executors
		local name = string.match(f, "([^/\\]+)%" .. ConfigurationExtension .. "$")
		if name and name ~= ".meta" then
			table.insert(result, name)
		end
	end
	table.sort(result)
	return result
end

-- Sauvegarde le slot auto-load pour ce jeu
local function _saveMeta()
	if not _hasFS then warn("[RV] _saveMeta : _hasFS false") return end
	if not CAutoloadFile then warn("[RV] _saveMeta : CAutoloadFile nil") return end
	local payload = HttpService:JSONEncode({ autoLoadSlot = CAutoLoadSlot or "" })
	local ok, err = pcall(writefile, CAutoloadFile, payload)
end

-- Charge le slot auto-load pour ce jeu
local function _loadMeta()
	if not _hasFS or not CAutoloadFile then return end
	local exists = isfile(CAutoloadFile)
	if not exists then return end
	local ok, data = pcall(function()
		return HttpService:JSONDecode(readfile(CAutoloadFile))
	end)
	if not ok or type(data) ~= "table" then return end
	CAutoLoadSlot = (type(data.autoLoadSlot) == "string" and data.autoLoadSlot ~= "") and data.autoLoadSlot or nil
end

local RayfieldLibrary = {
	Flags = {},
	Theme = {
		Default = {
			TextColor = Color3.fromRGB(240, 240, 240),

			Background = Color3.fromRGB(25, 25, 25),
			Topbar = Color3.fromRGB(34, 34, 34),
			Shadow = Color3.fromRGB(20, 20, 20),

			NotificationBackground = Color3.fromRGB(20, 20, 20),
			NotificationActionsBackground = Color3.fromRGB(230, 230, 230),

			TabBackground = Color3.fromRGB(80, 80, 80),
			TabStroke = Color3.fromRGB(85, 85, 85),
			TabBackgroundSelected = Color3.fromRGB(210, 210, 210),
			TabTextColor = Color3.fromRGB(240, 240, 240),
			SelectedTabTextColor = Color3.fromRGB(50, 50, 50),

			ElementBackground = Color3.fromRGB(35, 35, 35),
			ElementBackgroundHover = Color3.fromRGB(40, 40, 40),
			SecondaryElementBackground = Color3.fromRGB(25, 25, 25),
			ElementStroke = Color3.fromRGB(50, 50, 50),
			SecondaryElementStroke = Color3.fromRGB(40, 40, 40),

			SliderBackground = Color3.fromRGB(50, 138, 220),
			SliderProgress = Color3.fromRGB(50, 138, 220),
			SliderStroke = Color3.fromRGB(58, 163, 255),

			ToggleBackground = Color3.fromRGB(30, 30, 30),
			ToggleEnabled = Color3.fromRGB(0, 146, 214),
			ToggleDisabled = Color3.fromRGB(100, 100, 100),
			ToggleEnabledStroke = Color3.fromRGB(0, 170, 255),
			ToggleDisabledStroke = Color3.fromRGB(125, 125, 125),
			ToggleEnabledOuterStroke = Color3.fromRGB(100, 100, 100),
			ToggleDisabledOuterStroke = Color3.fromRGB(65, 65, 65),

			DropdownSelected = Color3.fromRGB(40, 40, 40),
			DropdownUnselected = Color3.fromRGB(30, 30, 30),

			InputBackground = Color3.fromRGB(30, 30, 30),
			InputStroke = Color3.fromRGB(65, 65, 65),
			PlaceholderColor = Color3.fromRGB(178, 178, 178)
		},

		Ocean = {
			TextColor = Color3.fromRGB(230, 240, 240),

			Background = Color3.fromRGB(20, 30, 30),
			Topbar = Color3.fromRGB(25, 40, 40),
			Shadow = Color3.fromRGB(15, 20, 20),

			NotificationBackground = Color3.fromRGB(25, 35, 35),
			NotificationActionsBackground = Color3.fromRGB(230, 240, 240),

			TabBackground = Color3.fromRGB(40, 60, 60),
			TabStroke = Color3.fromRGB(50, 70, 70),
			TabBackgroundSelected = Color3.fromRGB(100, 180, 180),
			TabTextColor = Color3.fromRGB(210, 230, 230),
			SelectedTabTextColor = Color3.fromRGB(20, 50, 50),

			ElementBackground = Color3.fromRGB(30, 50, 50),
			ElementBackgroundHover = Color3.fromRGB(40, 60, 60),
			SecondaryElementBackground = Color3.fromRGB(30, 45, 45),
			ElementStroke = Color3.fromRGB(45, 70, 70),
			SecondaryElementStroke = Color3.fromRGB(40, 65, 65),

			SliderBackground = Color3.fromRGB(0, 110, 110),
			SliderProgress = Color3.fromRGB(0, 140, 140),
			SliderStroke = Color3.fromRGB(0, 160, 160),

			ToggleBackground = Color3.fromRGB(30, 50, 50),
			ToggleEnabled = Color3.fromRGB(0, 130, 130),
			ToggleDisabled = Color3.fromRGB(70, 90, 90),
			ToggleEnabledStroke = Color3.fromRGB(0, 160, 160),
			ToggleDisabledStroke = Color3.fromRGB(85, 105, 105),
			ToggleEnabledOuterStroke = Color3.fromRGB(50, 100, 100),
			ToggleDisabledOuterStroke = Color3.fromRGB(45, 65, 65),

			DropdownSelected = Color3.fromRGB(30, 60, 60),
			DropdownUnselected = Color3.fromRGB(25, 40, 40),

			InputBackground = Color3.fromRGB(30, 50, 50),
			InputStroke = Color3.fromRGB(50, 70, 70),
			PlaceholderColor = Color3.fromRGB(140, 160, 160)
		},

		AmberGlow = {
			TextColor = Color3.fromRGB(255, 245, 230),

			Background = Color3.fromRGB(45, 30, 20),
			Topbar = Color3.fromRGB(55, 40, 25),
			Shadow = Color3.fromRGB(35, 25, 15),

			NotificationBackground = Color3.fromRGB(50, 35, 25),
			NotificationActionsBackground = Color3.fromRGB(245, 230, 215),

			TabBackground = Color3.fromRGB(75, 50, 35),
			TabStroke = Color3.fromRGB(90, 60, 45),
			TabBackgroundSelected = Color3.fromRGB(230, 180, 100),
			TabTextColor = Color3.fromRGB(250, 220, 200),
			SelectedTabTextColor = Color3.fromRGB(50, 30, 10),

			ElementBackground = Color3.fromRGB(60, 45, 35),
			ElementBackgroundHover = Color3.fromRGB(70, 50, 40),
			SecondaryElementBackground = Color3.fromRGB(55, 40, 30),
			ElementStroke = Color3.fromRGB(85, 60, 45),
			SecondaryElementStroke = Color3.fromRGB(75, 50, 35),

			SliderBackground = Color3.fromRGB(220, 130, 60),
			SliderProgress = Color3.fromRGB(250, 150, 75),
			SliderStroke = Color3.fromRGB(255, 170, 85),

			ToggleBackground = Color3.fromRGB(55, 40, 30),
			ToggleEnabled = Color3.fromRGB(240, 130, 30),
			ToggleDisabled = Color3.fromRGB(90, 70, 60),
			ToggleEnabledStroke = Color3.fromRGB(255, 160, 50),
			ToggleDisabledStroke = Color3.fromRGB(110, 85, 75),
			ToggleEnabledOuterStroke = Color3.fromRGB(200, 100, 50),
			ToggleDisabledOuterStroke = Color3.fromRGB(75, 60, 55),

			DropdownSelected = Color3.fromRGB(70, 50, 40),
			DropdownUnselected = Color3.fromRGB(55, 40, 30),

			InputBackground = Color3.fromRGB(60, 45, 35),
			InputStroke = Color3.fromRGB(90, 65, 50),
			PlaceholderColor = Color3.fromRGB(190, 150, 130)
		},

		Light = {
			TextColor = Color3.fromRGB(40, 40, 40),

			Background = Color3.fromRGB(245, 245, 245),
			Topbar = Color3.fromRGB(230, 230, 230),
			Shadow = Color3.fromRGB(200, 200, 200),

			NotificationBackground = Color3.fromRGB(250, 250, 250),
			NotificationActionsBackground = Color3.fromRGB(240, 240, 240),

			TabBackground = Color3.fromRGB(235, 235, 235),
			TabStroke = Color3.fromRGB(215, 215, 215),
			TabBackgroundSelected = Color3.fromRGB(255, 255, 255),
			TabTextColor = Color3.fromRGB(80, 80, 80),
			SelectedTabTextColor = Color3.fromRGB(0, 0, 0),

			ElementBackground = Color3.fromRGB(240, 240, 240),
			ElementBackgroundHover = Color3.fromRGB(225, 225, 225),
			SecondaryElementBackground = Color3.fromRGB(235, 235, 235),
			ElementStroke = Color3.fromRGB(210, 210, 210),
			SecondaryElementStroke = Color3.fromRGB(210, 210, 210),

			SliderBackground = Color3.fromRGB(150, 180, 220),
			SliderProgress = Color3.fromRGB(100, 150, 200), 
			SliderStroke = Color3.fromRGB(120, 170, 220),

			ToggleBackground = Color3.fromRGB(220, 220, 220),
			ToggleEnabled = Color3.fromRGB(0, 146, 214),
			ToggleDisabled = Color3.fromRGB(150, 150, 150),
			ToggleEnabledStroke = Color3.fromRGB(0, 170, 255),
			ToggleDisabledStroke = Color3.fromRGB(170, 170, 170),
			ToggleEnabledOuterStroke = Color3.fromRGB(100, 100, 100),
			ToggleDisabledOuterStroke = Color3.fromRGB(180, 180, 180),

			DropdownSelected = Color3.fromRGB(230, 230, 230),
			DropdownUnselected = Color3.fromRGB(220, 220, 220),

			InputBackground = Color3.fromRGB(240, 240, 240),
			InputStroke = Color3.fromRGB(180, 180, 180),
			PlaceholderColor = Color3.fromRGB(140, 140, 140)
		},

		Amethyst = {
			TextColor = Color3.fromRGB(240, 240, 240),

			Background = Color3.fromRGB(30, 20, 40),
			Topbar = Color3.fromRGB(40, 25, 50),
			Shadow = Color3.fromRGB(20, 15, 30),

			NotificationBackground = Color3.fromRGB(35, 20, 40),
			NotificationActionsBackground = Color3.fromRGB(240, 240, 250),

			TabBackground = Color3.fromRGB(60, 40, 80),
			TabStroke = Color3.fromRGB(70, 45, 90),
			TabBackgroundSelected = Color3.fromRGB(180, 140, 200),
			TabTextColor = Color3.fromRGB(230, 230, 240),
			SelectedTabTextColor = Color3.fromRGB(50, 20, 50),

			ElementBackground = Color3.fromRGB(45, 30, 60),
			ElementBackgroundHover = Color3.fromRGB(50, 35, 70),
			SecondaryElementBackground = Color3.fromRGB(40, 30, 55),
			ElementStroke = Color3.fromRGB(70, 50, 85),
			SecondaryElementStroke = Color3.fromRGB(65, 45, 80),

			SliderBackground = Color3.fromRGB(100, 60, 150),
			SliderProgress = Color3.fromRGB(130, 80, 180),
			SliderStroke = Color3.fromRGB(150, 100, 200),

			ToggleBackground = Color3.fromRGB(45, 30, 55),
			ToggleEnabled = Color3.fromRGB(120, 60, 150),
			ToggleDisabled = Color3.fromRGB(94, 47, 117),
			ToggleEnabledStroke = Color3.fromRGB(140, 80, 170),
			ToggleDisabledStroke = Color3.fromRGB(124, 71, 150),
			ToggleEnabledOuterStroke = Color3.fromRGB(90, 40, 120),
			ToggleDisabledOuterStroke = Color3.fromRGB(80, 50, 110),

			DropdownSelected = Color3.fromRGB(50, 35, 70),
			DropdownUnselected = Color3.fromRGB(35, 25, 50),

			InputBackground = Color3.fromRGB(45, 30, 60),
			InputStroke = Color3.fromRGB(80, 50, 110),
			PlaceholderColor = Color3.fromRGB(178, 150, 200)
		},

		Green = {
			TextColor = Color3.fromRGB(30, 60, 30),

			Background = Color3.fromRGB(235, 245, 235),
			Topbar = Color3.fromRGB(210, 230, 210),
			Shadow = Color3.fromRGB(200, 220, 200),

			NotificationBackground = Color3.fromRGB(240, 250, 240),
			NotificationActionsBackground = Color3.fromRGB(220, 235, 220),

			TabBackground = Color3.fromRGB(215, 235, 215),
			TabStroke = Color3.fromRGB(190, 210, 190),
			TabBackgroundSelected = Color3.fromRGB(245, 255, 245),
			TabTextColor = Color3.fromRGB(50, 80, 50),
			SelectedTabTextColor = Color3.fromRGB(20, 60, 20),

			ElementBackground = Color3.fromRGB(225, 240, 225),
			ElementBackgroundHover = Color3.fromRGB(210, 225, 210),
			SecondaryElementBackground = Color3.fromRGB(235, 245, 235), 
			ElementStroke = Color3.fromRGB(180, 200, 180),
			SecondaryElementStroke = Color3.fromRGB(180, 200, 180),

			SliderBackground = Color3.fromRGB(90, 160, 90),
			SliderProgress = Color3.fromRGB(70, 130, 70),
			SliderStroke = Color3.fromRGB(100, 180, 100),

			ToggleBackground = Color3.fromRGB(215, 235, 215),
			ToggleEnabled = Color3.fromRGB(60, 130, 60),
			ToggleDisabled = Color3.fromRGB(150, 175, 150),
			ToggleEnabledStroke = Color3.fromRGB(80, 150, 80),
			ToggleDisabledStroke = Color3.fromRGB(130, 150, 130),
			ToggleEnabledOuterStroke = Color3.fromRGB(100, 160, 100),
			ToggleDisabledOuterStroke = Color3.fromRGB(160, 180, 160),

			DropdownSelected = Color3.fromRGB(225, 240, 225),
			DropdownUnselected = Color3.fromRGB(210, 225, 210),

			InputBackground = Color3.fromRGB(235, 245, 235),
			InputStroke = Color3.fromRGB(180, 200, 180),
			PlaceholderColor = Color3.fromRGB(120, 140, 120)
		},

		Bloom = {
			TextColor = Color3.fromRGB(60, 40, 50),

			Background = Color3.fromRGB(255, 240, 245),
			Topbar = Color3.fromRGB(250, 220, 225),
			Shadow = Color3.fromRGB(230, 190, 195),

			NotificationBackground = Color3.fromRGB(255, 235, 240),
			NotificationActionsBackground = Color3.fromRGB(245, 215, 225),

			TabBackground = Color3.fromRGB(240, 210, 220),
			TabStroke = Color3.fromRGB(230, 200, 210),
			TabBackgroundSelected = Color3.fromRGB(255, 225, 235),
			TabTextColor = Color3.fromRGB(80, 40, 60),
			SelectedTabTextColor = Color3.fromRGB(50, 30, 50),

			ElementBackground = Color3.fromRGB(255, 235, 240),
			ElementBackgroundHover = Color3.fromRGB(245, 220, 230),
			SecondaryElementBackground = Color3.fromRGB(255, 235, 240), 
			ElementStroke = Color3.fromRGB(230, 200, 210),
			SecondaryElementStroke = Color3.fromRGB(230, 200, 210),

			SliderBackground = Color3.fromRGB(240, 130, 160),
			SliderProgress = Color3.fromRGB(250, 160, 180),
			SliderStroke = Color3.fromRGB(255, 180, 200),

			ToggleBackground = Color3.fromRGB(240, 210, 220),
			ToggleEnabled = Color3.fromRGB(255, 140, 170),
			ToggleDisabled = Color3.fromRGB(200, 180, 185),
			ToggleEnabledStroke = Color3.fromRGB(250, 160, 190),
			ToggleDisabledStroke = Color3.fromRGB(210, 180, 190),
			ToggleEnabledOuterStroke = Color3.fromRGB(220, 160, 180),
			ToggleDisabledOuterStroke = Color3.fromRGB(190, 170, 180),

			DropdownSelected = Color3.fromRGB(250, 220, 225),
			DropdownUnselected = Color3.fromRGB(240, 210, 220),

			InputBackground = Color3.fromRGB(255, 235, 240),
			InputStroke = Color3.fromRGB(220, 190, 200),
			PlaceholderColor = Color3.fromRGB(170, 130, 140)
		},

		DarkBlue = {
			TextColor = Color3.fromRGB(230, 230, 230),

			Background = Color3.fromRGB(20, 25, 30),
			Topbar = Color3.fromRGB(30, 35, 40),
			Shadow = Color3.fromRGB(15, 20, 25),

			NotificationBackground = Color3.fromRGB(25, 30, 35),
			NotificationActionsBackground = Color3.fromRGB(45, 50, 55),

			TabBackground = Color3.fromRGB(35, 40, 45),
			TabStroke = Color3.fromRGB(45, 50, 60),
			TabBackgroundSelected = Color3.fromRGB(40, 70, 100),
			TabTextColor = Color3.fromRGB(200, 200, 200),
			SelectedTabTextColor = Color3.fromRGB(255, 255, 255),

			ElementBackground = Color3.fromRGB(30, 35, 40),
			ElementBackgroundHover = Color3.fromRGB(40, 45, 50),
			SecondaryElementBackground = Color3.fromRGB(35, 40, 45), 
			ElementStroke = Color3.fromRGB(45, 50, 60),
			SecondaryElementStroke = Color3.fromRGB(40, 45, 55),

			SliderBackground = Color3.fromRGB(0, 90, 180),
			SliderProgress = Color3.fromRGB(0, 120, 210),
			SliderStroke = Color3.fromRGB(0, 150, 240),

			ToggleBackground = Color3.fromRGB(35, 40, 45),
			ToggleEnabled = Color3.fromRGB(0, 120, 210),
			ToggleDisabled = Color3.fromRGB(70, 70, 80),
			ToggleEnabledStroke = Color3.fromRGB(0, 150, 240),
			ToggleDisabledStroke = Color3.fromRGB(75, 75, 85),
			ToggleEnabledOuterStroke = Color3.fromRGB(20, 100, 180), 
			ToggleDisabledOuterStroke = Color3.fromRGB(55, 55, 65),

			DropdownSelected = Color3.fromRGB(30, 70, 90),
			DropdownUnselected = Color3.fromRGB(25, 30, 35),

			InputBackground = Color3.fromRGB(25, 30, 35),
			InputStroke = Color3.fromRGB(45, 50, 60), 
			PlaceholderColor = Color3.fromRGB(150, 150, 160)
		},

		Serenity = {
			TextColor = Color3.fromRGB(50, 55, 60),
			Background = Color3.fromRGB(240, 245, 250),
			Topbar = Color3.fromRGB(215, 225, 235),
			Shadow = Color3.fromRGB(200, 210, 220),

			NotificationBackground = Color3.fromRGB(210, 220, 230),
			NotificationActionsBackground = Color3.fromRGB(225, 230, 240),

			TabBackground = Color3.fromRGB(200, 210, 220),
			TabStroke = Color3.fromRGB(180, 190, 200),
			TabBackgroundSelected = Color3.fromRGB(175, 185, 200),
			TabTextColor = Color3.fromRGB(50, 55, 60),
			SelectedTabTextColor = Color3.fromRGB(30, 35, 40),

			ElementBackground = Color3.fromRGB(210, 220, 230),
			ElementBackgroundHover = Color3.fromRGB(220, 230, 240),
			SecondaryElementBackground = Color3.fromRGB(200, 210, 220),
			ElementStroke = Color3.fromRGB(190, 200, 210),
			SecondaryElementStroke = Color3.fromRGB(180, 190, 200),

			SliderBackground = Color3.fromRGB(200, 220, 235),  -- Lighter shade
			SliderProgress = Color3.fromRGB(70, 130, 180),
			SliderStroke = Color3.fromRGB(150, 180, 220),

			ToggleBackground = Color3.fromRGB(210, 220, 230),
			ToggleEnabled = Color3.fromRGB(70, 160, 210),
			ToggleDisabled = Color3.fromRGB(180, 180, 180),
			ToggleEnabledStroke = Color3.fromRGB(60, 150, 200),
			ToggleDisabledStroke = Color3.fromRGB(140, 140, 140),
			ToggleEnabledOuterStroke = Color3.fromRGB(100, 120, 140),
			ToggleDisabledOuterStroke = Color3.fromRGB(120, 120, 130),

			DropdownSelected = Color3.fromRGB(220, 230, 240),
			DropdownUnselected = Color3.fromRGB(200, 210, 220),

			InputBackground = Color3.fromRGB(220, 230, 240),
			InputStroke = Color3.fromRGB(180, 190, 200),
			PlaceholderColor = Color3.fromRGB(150, 150, 150)
		},
	}
}




-- Interface Management

local RayfieldAssetId = customAssetId or 10804731440
local Rayfield = useStudio and script.Parent:FindFirstChild('Rayfield') or game:GetObjects("rbxassetid://"..RayfieldAssetId)[1]
local buildAttempts = 0
local correctBuild = false
local warned
local globalLoaded
local rayfieldDestroyed = false -- True when RayfieldLibrary:Destroy() is called

-- ════════════════════════════════════════════════════════════════════════════
--  SIDE TAB MODE — activé via SideTabs = true dans CreateWindow
-- ════════════════════════════════════════════════════════════════════════════
local _sideTabMode  = false  -- true si tabs sur le côté gauche
local _sideTabWidth = 130    -- largeur de la sidebar en pixels

repeat
	if Rayfield:FindFirstChild('Build') and Rayfield.Build.Value == InterfaceBuild then
		correctBuild = true
		break
	end

	correctBuild = false

	if not warned then
		warn('Rayfield | Build Mismatch')
		warned = true
	end

	local toDestroy
	toDestroy, Rayfield = Rayfield, useStudio and script.Parent:FindFirstChild('Rayfield') or game:GetObjects("rbxassetid://"..RayfieldAssetId)[1]
	if toDestroy and not useStudio then toDestroy:Destroy() end

	buildAttempts = buildAttempts + 1
until buildAttempts >= 2

Rayfield.Enabled = false

if gethui then
	Rayfield.Parent = gethui()
elseif syn and syn.protect_gui then 
	syn.protect_gui(Rayfield)
	Rayfield.Parent = CoreGui
elseif not useStudio and CoreGui:FindFirstChild("RobloxGui") then
	Rayfield.Parent = CoreGui:FindFirstChild("RobloxGui")
elseif not useStudio then
	Rayfield.Parent = CoreGui
end

if gethui then
	for _, Interface in ipairs(gethui():GetChildren()) do
		if Interface.Name == Rayfield.Name and Interface ~= Rayfield then
			Interface.Enabled = false
			Interface.Name = "Rayfield-Old"
		end
	end
elseif not useStudio then
	for _, Interface in ipairs(CoreGui:GetChildren()) do
		if Interface.Name == Rayfield.Name and Interface ~= Rayfield then
			Interface.Enabled = false
			Interface.Name = "Rayfield-Old"
		end
	end
end

if secureMode and not customAssetId then
	secureNotify("default_asset", "Secure Mode", "You are using the default Rayfield asset ID. Set RAYFIELD_ASSET_ID to a custom upload to avoid detection.")
end

do
	local AssetPath = RayfieldFolder.."/Assets"
	local AssetBaseURL = "https://github.com/SiriusSoftwareLtd/Rayfield/blob/main/assets/"

	local assetFiles = {
		["111263549366178"] = AssetBaseURL.."111263549366178.png?raw=true",
		["77891951053543"] = AssetBaseURL.."77891951053543.png?raw=true",
		["78137979054938"] = AssetBaseURL.."78137979054938.png?raw=true",
		["80503127983237"] = AssetBaseURL.."80503127983237.png?raw=true",
		["10137832201"] = AssetBaseURL.."10137832201.png?raw=true",
		["10137941941"] = AssetBaseURL.."10137941941.png?raw=true",
		["11036884234"] = AssetBaseURL.."11036884234.png?raw=true",
		["11413591840"] = AssetBaseURL.."11413591840.png?raw=true",
		["11745872910"] = AssetBaseURL.."11745872910.png?raw=true",
		["12577727209"] = AssetBaseURL.."12577727209.png?raw=true",
		["18458939117"] = AssetBaseURL.."18458939117.png?raw=true",
		["3259050989"] = AssetBaseURL.."3259050989.png?raw=true",
		["3523728077"] = AssetBaseURL.."3523728077.png?raw=true",
		["3602733521"] = AssetBaseURL.."3602733521.png?raw=true",
		["IconChevronTopMedium"] = AssetBaseURL.."IconChevronTopMedium.png?raw=true",
		["4483362458"] = AssetBaseURL.."4483362458.png?raw=true",
		["5587865193"] = AssetBaseURL.."5587865193.png?raw=true",
		["IconMagnifyingGlass2"] = AssetBaseURL.."IconMagnifyingGlass2.png?raw=true",
	}

	for id, _ in assetFiles do
		customAssets[tostring(id)] = ""
	end

	local hasCustomAsset = type(getcustomasset) == "function"
	local hasFilesystem = type(writefile) == "function" and type(makefolder) == "function" and type(isfile) == "function" and type(isfolder) == "function"

	if hasCustomAsset and hasFilesystem then
		local ok, err = pcall(function()
			ensureFolder(RayfieldFolder)
			ensureFolder(AssetPath)

			local function nextMissing()
				for id, _ in assetFiles do
					if not isfile(AssetPath.."/"..tostring(id)..".png") then
						return id
					end
				end
				return nil
			end

			if nextMissing() then
				task.spawn(function()
					while true do
						local id = nextMissing()
						if not id then break end
						writefile(AssetPath.."/"..tostring(id)..".png", requestFunc({Url = assetFiles[id], Method = "GET"}).Body)
						task.wait()
					end
				end)

				while nextMissing() do
					task.wait(0.1)
				end
			end

			for id, _ in assetFiles do
				local success, asset = pcall(getcustomasset, AssetPath.."/"..tostring(id)..".png")
				if success then
					customAssets[tostring(id)] = asset
				else
					warn("Rayfield | Failed to load custom asset: "..tostring(id).." - "..tostring(asset))
				end
			end
		end)

		if not ok then
			warn("Rayfield | Failed to load custom assets: "..tostring(err))
			secureNotify("asset_load_fail", "Rayfield", "Failed to load custom assets. UI images may not display correctly.")
		end
	else
		secureNotify("no_getcustomasset", "Rayfield", "Your executor does not support getcustomasset. Some UI images may not render correctly.")
	end


	Rayfield.Main.Shadow.Image.Image = customAssets[tostring(5587865193)]
	Rayfield.Main.Topbar.Hide.Image = customAssets[tostring(10137832201)]
	Rayfield.Main.Topbar.ChangeSize.Image = customAssets[tostring(10137941941)]
	Rayfield.Main.Topbar.Settings.Image = customAssets[tostring(80503127983237)]
	Rayfield.Main.Topbar.Icon.Image = customAssets[tostring(78137979054938)]
	Rayfield.Main.Topbar.Search.Image = customAssets["IconMagnifyingGlass2"]
	Rayfield.Main.Topbar.Search.ImageRectOffset = Vector2.new(0, 0)
	Rayfield.Main.Topbar.Search.ImageRectSize = Vector2.new(0, 0)
	Rayfield.Main.Elements.Template.Toggle.Switch.Shadow.Image = customAssets[tostring(3602733521)]
	Rayfield.Main.Elements.Template.Slider.Main.Shadow.Image = customAssets[tostring(3602733521)]
	Rayfield.Main.Elements.Template.Dropdown.Toggle.Image = customAssets["IconChevronTopMedium"]
	Rayfield.Main.Elements.Template.Dropdown.Toggle.ImageRectOffset = Vector2.new(0, 0)
	Rayfield.Main.Elements.Template.Dropdown.Toggle.ImageRectSize = Vector2.new(0, 0)
	Rayfield.Main.Elements.Template.Label.Icon.Image = customAssets[tostring(11745872910)]
	Rayfield.Main.Elements.Template.ColorPicker.CPBackground.MainCP.Image = customAssets[tostring(11413591840)]
	Rayfield.Main.Elements.Template.ColorPicker.CPBackground.MainCP.MainPoint.Image = customAssets[tostring(3259050989)]
	Rayfield.Main.Elements.Template.ColorPicker.ColorSlider.SliderPoint.Image = customAssets[tostring(3259050989)]
	Rayfield.Main.TabList.Template.Image.Image = customAssets[tostring(4483362458)]
	Rayfield.Main.Search.Search.Image = customAssets[tostring(18458939117)]
	Rayfield.Main.Search.Shadow.Image = customAssets[tostring(5587865193)]
	Rayfield.Notifications.Template.Icon.Image = customAssets[tostring(77891951053543)]
	Rayfield.Notifications.Template.Shadow.Image = customAssets[tostring(3523728077)]
	Rayfield.Loading.Banner.Image = customAssets[tostring(111263549366178)]

end -- custom asset block

local minSize = Vector2.new(1024, 768)
local useMobileSizing

if Rayfield.AbsoluteSize.X < minSize.X and Rayfield.AbsoluteSize.Y < minSize.Y then
	useMobileSizing = true
end

local useMobilePrompt = false
if UserInputService.TouchEnabled then
	useMobilePrompt = true
end


-- Object Variables

local Main = Rayfield.Main
local MPrompt = Rayfield:FindFirstChild('Prompt')
local Topbar = Main.Topbar
local Elements = Main.Elements
local LoadingFrame = Main.LoadingFrame
local TabList = Main.TabList
local dragBar = Rayfield:FindFirstChild('Drag')
local dragInteract = dragBar and dragBar.Interact or nil
local dragBarCosmetic = dragBar and dragBar.Drag or nil

local dragOffset = 255
local dragOffsetMobile = 150

Rayfield.DisplayOrder = 100
LoadingFrame.Version.Text = Release

-- Thanks to Latte Softworks for the Lucide integration for Roblox
local Icons = useStudio and require(script.Parent.icons) or loadWithTimeout('https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/refs/heads/main/icons.lua')
-- Variables
-- CActiveSlot, CEnabled, CAutoLoadSlot, _hasFS, _pendingTheme déclarés en haut du fichier

-- ── UI READY DETECTOR ────────────────────────────────────────────────────────
local _lastComponentTime = 0
local UI_READY_DELAY     = 0.5
local _uiReadyFired      = false
local function _onComponentCreated()
	_lastComponentTime = tick()
end
local Minimised = false
local Hidden = false
local Debounce = false
local searchOpen = false
local Notifications = Rayfield.Notifications
local keybindConnections = {} -- For storing keybind connections to disconnect when Rayfield is destroyed

-- ════════════════════════════════════════════════════════════════════════════
--  FLOATING REOPEN BUTTON — apparaît quand Hidden=true, disparaît sinon
-- ════════════════════════════════════════════════════════════════════════════
local _reopenSg = Instance.new("ScreenGui")
_reopenSg.Name = "Rayfield_ReopenBtn"
_reopenSg.ResetOnSpawn = false
_reopenSg.DisplayOrder = 9998
local _reopenOk = pcall(function() _reopenSg.Parent = CoreGui end)
if not _reopenOk then _reopenSg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

local _reopenBtn = Instance.new("ImageButton")
_reopenBtn.Name = "ReopenButton"
_reopenBtn.Size = UDim2.new(0, 50, 0, 50)
_reopenBtn.Position = UDim2.new(0, 20, 0.5, -25)
_reopenBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
_reopenBtn.BackgroundTransparency = 1
_reopenBtn.Image = "rbxassetid://0"  -- << remplace par ton rbxassetid ici
_reopenBtn.ImageTransparency = 1
_reopenBtn.Visible = false
_reopenBtn.Parent = _reopenSg

local _reopenCorner = Instance.new("UICorner")
_reopenCorner.CornerRadius = UDim.new(0, 10)
_reopenCorner.Parent = _reopenBtn

local _hasImage = _reopenBtn.Image ~= "" and _reopenBtn.Image ~= "rbxassetid://0"

local function _showReopenBtn()
	_reopenBtn.Visible = true
	if _hasImage then
		TweenService:Create(_reopenBtn, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {ImageTransparency = 0, BackgroundTransparency = 1}):Play()
	else
		TweenService:Create(_reopenBtn, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.2}):Play()
	end
end

local function _hideReopenBtn()
	if _hasImage then
		TweenService:Create(_reopenBtn, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
	else
		TweenService:Create(_reopenBtn, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	end
	task.spawn(function()
		task.wait(0.4)
		_reopenBtn.Visible = false
	end)
end

local SelectedTheme = RayfieldLibrary.Theme.Default

ChangeTheme = function(Theme)
	if typeof(Theme) == 'string' then
		local resolved = RayfieldLibrary.Theme[Theme]
		if not resolved then
			local available = {}
			for k, _ in pairs(RayfieldLibrary.Theme) do table.insert(available, k) end
			warn("[RV] ChangeTheme : thème introuvable → " .. tostring(Theme))
			error("theme not found")
		end
		SelectedTheme = resolved
		_currentThemeName = Theme  -- on stocke le nom directement
	elseif typeof(Theme) == 'table' then
		SelectedTheme = Theme
		-- thème custom sans nom — on garde le nom précédent
	end

	-- Synchronise VC avec le thème courant (composants VoidUI custom)
	VC.BgDeep     = SelectedTheme.Background
	VC.BgMid      = SelectedTheme.ElementBackground
	VC.BgLight    = SelectedTheme.ElementBackgroundHover
	VC.BgLighter  = SelectedTheme.SecondaryElementBackground or SelectedTheme.ElementBackgroundHover
	VC.Accent     = SelectedTheme.SliderProgress
	VC.AccentSoft = SelectedTheme.SliderBackground
	VC.AccentPink = SelectedTheme.SliderStroke
	VC.AccentGlow = SelectedTheme.SliderStroke
	VC.TextBright = SelectedTheme.TextColor
	VC.TextMid    = Color3.new(
		SelectedTheme.TextColor.R * 0.65,
		SelectedTheme.TextColor.G * 0.65,
		SelectedTheme.TextColor.B * 0.65
	)
	VC.BorderDim  = SelectedTheme.ElementStroke

	Rayfield.Main.BackgroundColor3 = SelectedTheme.Background
	Rayfield.Main.Topbar.BackgroundColor3 = SelectedTheme.Topbar
	Rayfield.Main.Topbar.CornerRepair.BackgroundColor3 = SelectedTheme.Topbar
	Rayfield.Main.Shadow.Image.ImageColor3 = SelectedTheme.Shadow

	Rayfield.Main.Topbar.ChangeSize.ImageColor3 = SelectedTheme.TextColor
	Rayfield.Main.Topbar.Hide.ImageColor3 = SelectedTheme.TextColor
	Rayfield.Main.Topbar.Search.ImageColor3 = SelectedTheme.TextColor
	if Topbar:FindFirstChild('Settings') then
		Rayfield.Main.Topbar.Settings.ImageColor3 = SelectedTheme.TextColor
		Rayfield.Main.Topbar.Divider.BackgroundColor3 = SelectedTheme.ElementStroke
	end

	Main.Search.BackgroundColor3 = SelectedTheme.TextColor
	Main.Search.Shadow.ImageColor3 = SelectedTheme.TextColor
	Main.Search.Search.ImageColor3 = SelectedTheme.TextColor
	Main.Search.Input.PlaceholderColor3 = SelectedTheme.TextColor
	Main.Search.UIStroke.Color = SelectedTheme.SecondaryElementStroke

	if Main:FindFirstChild('Notice') then
		Main.Notice.BackgroundColor3 = SelectedTheme.Background
	end

	for _, text in ipairs(Rayfield:GetDescendants()) do
		if text.Parent.Parent ~= Notifications then
			if text:IsA('TextLabel') or text:IsA('TextBox') then text.TextColor3 = SelectedTheme.TextColor end
		end
	end

	for _, TabPage in ipairs(Elements:GetChildren()) do
		for _, Element in ipairs(TabPage:GetChildren()) do
			if Element.ClassName == "Frame" and Element.Name ~= "Placeholder" and Element.Name ~= "SectionSpacing" and Element.Name ~= "Divider" and Element.Name ~= "SectionTitle" and Element.Name ~= "SearchTitle-fsefsefesfsefesfesfThanks" then
				Element.BackgroundColor3 = SelectedTheme.ElementBackground
				local elStroke = Element:FindFirstChildOfClass("UIStroke")
				if elStroke then
					elStroke.Color = SelectedTheme.ElementStroke
				end
			end

			-- Re-stylage des composants VoidUI custom (ProgressBar, MultiToggle, FilteredCardGrid_Ctrl)
			if Element.Name == "ProgressBar" then
				Element.BackgroundColor3 = SelectedTheme.ElementBackground
				local stroke = Element:FindFirstChildOfClass("UIStroke")
				if stroke then stroke.Color = SelectedTheme.ElementStroke end
				-- track = premier Frame enfant sans gradient
				for _, child in ipairs(Element:GetChildren()) do
					if child:IsA("Frame") and child.Name ~= "AccentBar" then
						-- fill bar (a gradient) ou track
						local grad = child:FindFirstChildOfClass("UIGradient")
						if grad then
							-- c'est le fill — gradient accent
							grad.Color = ColorSequence.new(VC.Accent, VC.AccentPink)
						else
							-- c'est le track
							child.BackgroundColor3 = SelectedTheme.Background
						end
					end
				end
			elseif Element.Name == "MultiToggle" then
				-- rows de MultiToggle
				for _, row in ipairs(Element:GetChildren()) do
					if row:IsA("Frame") then
						row.BackgroundColor3 = SelectedTheme.ElementBackground
						local stroke = row:FindFirstChildOfClass("UIStroke")
						if stroke then stroke.Color = SelectedTheme.ElementStroke end
						-- pill toggle
						for _, child in ipairs(row:GetChildren()) do
							if child:IsA("Frame") and child.Name ~= "AccentBar" then
								-- c'est le pill (off = BgDeep, on = Accent)
								-- on le remet en off par défaut si transparent
								if child.BackgroundColor3 ~= VC.Accent then
									child.BackgroundColor3 = SelectedTheme.Background
								else
									child.BackgroundColor3 = VC.Accent
								end
							end
						end
					end
				end
			elseif Element.Name == "FilteredCardGrid_Ctrl" then
				for _, child in ipairs(Element:GetChildren()) do
					if child:IsA("Frame") then
						child.BackgroundColor3 = SelectedTheme.ElementBackgroundHover
						local stroke = child:FindFirstChildOfClass("UIStroke")
						if stroke then stroke.Color = SelectedTheme.ElementStroke end
					end
				end
			end
		end
	end

	-- Re-stylage des barres d'accent VoidUI (UIGradient Accent→AccentPink)
	for _, TabPage in ipairs(Elements:GetChildren()) do
		for _, bar in ipairs(TabPage:GetDescendants()) do
			if bar:IsA("Frame") and bar.Name == "AccentBar" then
				local grad = bar:FindFirstChildOfClass("UIGradient")
				if grad then
					grad.Color = ColorSequence.new(VC.Accent, VC.AccentPink)
				end
			end
		end
	end

	-- Re-stylage des toggles selon leur état actuel
	for _, TabPage in ipairs(Elements:GetChildren()) do
		for _, Toggle in ipairs(TabPage:GetChildren()) do
			if Toggle:IsA("Frame") and Toggle:FindFirstChild("Switch") then
				local Switch = Toggle.Switch
				local Indicator = Switch:FindFirstChild("Indicator")
				if not Indicator then continue end
				local isEnabled = Indicator.Position.X.Offset == -20
				Switch.BackgroundColor3 = SelectedTheme.ToggleBackground
				if isEnabled then
					Indicator.BackgroundColor3 = SelectedTheme.ToggleEnabled
					Indicator.UIStroke.Color = SelectedTheme.ToggleEnabledStroke
					Switch.UIStroke.Color = SelectedTheme.ToggleEnabledOuterStroke
				else
					Indicator.BackgroundColor3 = SelectedTheme.ToggleDisabled
					Indicator.UIStroke.Color = SelectedTheme.ToggleDisabledStroke
					Switch.UIStroke.Color = SelectedTheme.ToggleDisabledOuterStroke
				end
			end
		end
	end

	-- Sauvegarde du thème dans les prefs globales
	_saveVoidPrefs()
end

local function getIcon(name : string): {id: number, imageRectSize: Vector2, imageRectOffset: Vector2}
	if not Icons then
		warn("Lucide Icons: Cannot use icons as icons library is not loaded")
		return
	end
	name = string.match(string.lower(name), "^%s*(.*)%s*$") :: string
	local sizedicons = Icons['48px']
	local r = sizedicons[name]
	if not r then
		error("Lucide Icons: Failed to find icon by the name of \"" .. name .. "\"", 2)
	end

	local rirs = r[2]
	local riro = r[3]

	if type(r[1]) ~= "number" or type(rirs) ~= "table" or type(riro) ~= "table" then
		error("Lucide Icons: Internal error: Invalid auto-generated asset entry")
	end

	local irs = Vector2.new(rirs[1], rirs[2])
	local iro = Vector2.new(riro[1], riro[2])

	local asset = {
		id = r[1],
		imageRectSize = irs,
		imageRectOffset = iro,
	}

	return asset
end
local function getAssetUri(id: any): string
	local assetUri = ""
	if type(id) == "number" then
		assetUri = "rbxassetid://" .. id
	elseif type(id) == "string" and not Icons then
		warn("Rayfield | Cannot use Lucide icons as icons library is not loaded")
	else
		warn("Rayfield | The icon argument must either be an icon ID (number) or a Lucide icon name (string)")
	end
	return assetUri
end

local function isCustomAsset(value)
	return type(value) == "string" and (string.find(value, "rbxasset://") == 1 or string.find(value, "rbxthumb://") == 1)
end

local function resolveIcon(icon)
	if not icon or icon == 0 then
		return "", nil, nil
	end

	if isCustomAsset(icon) then
		return icon, nil, nil
	end

	if secureMode then
		secureNotify("icon_blocked", "Secure Mode", "Element icons using asset IDs or Lucide names are blocked. Use getcustomasset() for icons to stay undetected.")
		return "", nil, nil
	end

	if typeof(icon) == "string" and Icons then
		local asset = getIcon(icon)
		return "rbxassetid://" .. asset.id, asset.imageRectOffset, asset.imageRectSize
	else
		return getAssetUri(icon), nil, nil
	end
end

local function makeDraggable(object, dragObject, enableTaptic, tapticOffset)
	local dragging = false
	local relative = nil

	local offset = Vector2.zero
	local screenGui = object:FindFirstAncestorWhichIsA("ScreenGui")
	if screenGui and screenGui.IgnoreGuiInset then
		offset += getService('GuiService'):GetGuiInset()
	end

	local function connectFunctions()
		if dragBar and enableTaptic then
			dragBar.MouseEnter:Connect(function()
				if not dragging and not Hidden then
					TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.5, Size = UDim2.new(0, 120, 0, 4)}):Play()
				end
			end)

			dragBar.MouseLeave:Connect(function()
				if not dragging and not Hidden then
					TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.7, Size = UDim2.new(0, 100, 0, 4)}):Play()
				end
			end)
		end
	end

	connectFunctions()

	dragObject.InputBegan:Connect(function(input, processed)
		if processed then return end

		local inputType = input.UserInputType.Name
		if inputType == "MouseButton1" or inputType == "Touch" then
			dragging = true

			relative = object.AbsolutePosition + object.AbsoluteSize * object.AnchorPoint - UserInputService:GetMouseLocation()
			if enableTaptic and not Hidden then
				TweenService:Create(dragBarCosmetic, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 110, 0, 4), BackgroundTransparency = 0}):Play()
			end
		end
	end)

	local inputEnded = UserInputService.InputEnded:Connect(function(input)
		if not dragging then return end

		local inputType = input.UserInputType.Name
		if inputType == "MouseButton1" or inputType == "Touch" then
			dragging = false

			if enableTaptic and not Hidden then
				TweenService:Create(dragBarCosmetic, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Size = UDim2.new(0, 100, 0, 4), BackgroundTransparency = 0.7}):Play()
			end
		end
	end)

	local renderStepped = RunService.RenderStepped:Connect(function()
		if dragging and not Hidden then
			local position = UserInputService:GetMouseLocation() + relative + offset
			if enableTaptic and tapticOffset then
				TweenService:Create(object, TweenInfo.new(0.4, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Position = UDim2.fromOffset(position.X, position.Y)}):Play()
				TweenService:Create(dragObject.Parent, TweenInfo.new(0.05, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Position = UDim2.fromOffset(position.X, position.Y + ((useMobileSizing and tapticOffset[2]) or tapticOffset[1]))}):Play()
			else
				if dragBar and tapticOffset then
					dragBar.Position = UDim2.fromOffset(position.X, position.Y + ((useMobileSizing and tapticOffset[2]) or tapticOffset[1]))
				end
				object.Position = UDim2.fromOffset(position.X, position.Y)
			end
		end
	end)

	object.Destroying:Connect(function()
		if inputEnded then inputEnded:Disconnect() end
		if renderStepped then renderStepped:Disconnect() end
	end)
end


local function PackColor(Color)
	return {R = Color.R * 255, G = Color.G * 255, B = Color.B * 255}
end    

local function UnpackColor(Color)
	return Color3.fromRGB(Color.R, Color.G, Color.B)
end

-- Charge une configuration depuis son contenu JSON.
-- Retourne { errors = {flagName,...} } — errors vide = succès total.
-- Applies a single flag's value. Returns true on success, false if Set() threw.
local function _applyFlag(Flag, FlagValue)
	return pcall(function()
		if Flag.Type == "ColorPicker" then
			Flag:Set(UnpackColor(FlagValue))
		elseif Flag.Type == "ProgressBar" then
			if Flag.SetValue then Flag:SetValue(tonumber(FlagValue) or 0) end
		elseif Flag.Type == "MultiToggle" then
			if Flag.SetValue and type(FlagValue) == "table" then Flag:SetValue(FlagValue) end
		elseif Flag.Type == "CardGrid" or Flag.Type == "FilteredCardGrid" then
			if Flag.SetSelected and type(FlagValue) == "table" then Flag:SetSelected(FlagValue) end
		else
			Flag:Set(FlagValue)
		end
	end)
end

-- retry: when true (auto-load), flags whose callback throws are retried a few
-- times with a short wait. This handles callbacks that only fail because the
-- game isn't ready yet right after injection (character/remotes/workspace not
-- loaded). Manual load passes retry=false because the game is already settled.
local function LoadConfiguration(rawContent, retry)
	local ok, parsed = pcall(function() return HttpService:JSONDecode(rawContent) end)
	if not ok or type(parsed) ~= "table" then
		return nil, {"Invalid JSON"}
	end

	-- Embedded placeId check
	if parsed.placeId ~= nil and parsed.placeId ~= game.PlaceId then
		return nil, {"PlaceId mismatch (" .. tostring(parsed.placeId) .. " ~= " .. tostring(game.PlaceId) .. ")"}
	end

	-- Support old (flat) and new {placeId, flags} formats
	local Data = parsed.flags or parsed

	-- Avale les notifs des callbacks rejoués pendant toute la restauration
	_suppressNotify = true

	-- First pass: apply everything with a known flag, collect flags whose
	-- callback threw. Flags not yet in RayfieldLibrary.Flags (component not
	-- built yet — e.g. a CardGrid created inside a deferred task.spawn that's
	-- still waiting on WaitForChild/retries) are queued as "missing" instead
	-- of being silently dropped, so the retry pass below gets a chance to
	-- pick them up once the component finally registers.
	local pending = {}  -- { {name=, flag=Flag, value=FlagValue}, ... } - Flag known, Set() threw
	local missing = {}  -- { {name=, value=FlagValue}, ... } - Flag not registered yet
	for FlagName, FlagValue in pairs(Data) do
		local Flag = RayfieldLibrary.Flags[FlagName]
		if Flag then
			if not _applyFlag(Flag, FlagValue) then
				table.insert(pending, { name = FlagName, flag = Flag, value = FlagValue })
			end
		else
			table.insert(missing, { name = FlagName, value = FlagValue })
		end
	end

	-- Retry pass (auto-load only): give the game (and deferred UI components)
	-- time to settle, retry both failures and previously-missing flags.
	if retry and (#pending > 0 or #missing > 0) then
		local maxAttempts = 12
		local waitBetween = 0.6
		for _ = 1, maxAttempts do
			if #pending == 0 and #missing == 0 then break end
			task.wait(waitBetween)

			local stillPending = {}
			for _, entry in ipairs(pending) do
				if not _applyFlag(entry.flag, entry.value) then
					table.insert(stillPending, entry)
				end
			end
			pending = stillPending

			local stillMissing = {}
			for _, entry in ipairs(missing) do
				local Flag = RayfieldLibrary.Flags[entry.name]
				if Flag then
					if not _applyFlag(Flag, entry.value) then
						table.insert(pending, { name = entry.name, flag = Flag, value = entry.value })
					end
				else
					table.insert(stillMissing, entry)
				end
			end
			missing = stillMissing
		end
	end

	-- Whatever flag is still missing after all retries really doesn't exist
	-- (game update / component removed) — fold it into pending so it's
	-- reported the same way as a failed Set().
	for _, entry in ipairs(missing) do
		table.insert(pending, { name = entry.name })
	end

	-- Restauration terminée → on réautorise les notifs
	_suppressNotify = false

	-- Whatever is left really failed
	local errors = {}
	for _, entry in ipairs(pending) do
		table.insert(errors, entry.name)
	end

	return true, errors
end

-- Partage de config entre joueurs, via le worker voidhub-configs. Tout est
-- regroupé dans une table locale : le fichier a déjà beaucoup de locals
-- au niveau module, une par fonction ferait grimper le compte pour rien.
-- `script` est rempli par SetScriptName (déclaré plus bas dans le fichier).
local _cfgShare = { baseUrl = "https://cfg.akkiwi.com", script = nil }

-- Snapshot des flags, exactement le contenu écrit dans les .rfld.
function _cfgShare.snapshot()
	local flags = {}
	for i, v in pairs(RayfieldLibrary.Flags) do
		if v.Type == "ColorPicker" then
			flags[i] = PackColor(v.Color)
		elseif v.Type == "ProgressBar" then
			flags[i] = v.GetValue and v:GetValue() or 0
		elseif v.Type == "MultiToggle" then
			flags[i] = v.GetValue and v:GetValue() or {}
		elseif v.Type == "CardGrid" or v.Type == "FilteredCardGrid" then
			flags[i] = v.GetSelected and v:GetSelected() or {}
		else
			if typeof(v.CurrentValue) == "boolean" then
				flags[i] = v.CurrentValue
			else
				flags[i] = v.CurrentValue or v.CurrentKeybind or v.CurrentOption or v.Color
			end
		end
	end
	return flags
end

function _cfgShare.request(method, url, body)
	local fn = (syn and syn.request) or (http and http.request) or http_request or request
	if not fn then return nil, "Your executor cannot send HTTP requests." end

	local opts = {
		Url     = url,
		Method  = method,
		Headers = { ["Content-Type"] = "application/json", ["Accept"] = "application/json" },
	}
	if body then opts.Body = HttpService:JSONEncode(body) end

	local ok, res = pcall(fn, opts)
	if not ok or type(res) ~= "table" then return nil, "Could not reach the config server." end

	local parsed
	pcall(function() parsed = HttpService:JSONDecode(res.Body or res.body or "") end)
	if type(parsed) ~= "table" then
		return nil, "Bad answer from the config server (" .. tostring(res.StatusCode or res.status_code or "?") .. ")."
	end
	if parsed.ok ~= true then return nil, tostring(parsed.error or "Request refused.") end
	return parsed
end

function _cfgShare.push(name)
	local flags = _cfgShare.snapshot()
	if not next(flags) then return nil, "Nothing to share yet." end
	return _cfgShare.request("POST", _cfgShare.baseUrl .. "/share", {
		place_id = tostring(game.PlaceId),
		game_id  = tostring(game.GameId),
		script   = _cfgShare.script,
		name     = name,
		config   = { placeId = game.PlaceId, flags = flags },
	})
end

-- Accepte le code seul ("AB3D7KP2") comme le lien complet du worker.
function _cfgShare.parseCode(input)
	local s = tostring(input or ""):gsub("%s", "")
	s = s:gsub("%?.*$", "")
	s = s:match("([^/]+)$") or s
	s = s:gsub("[^%w]", ""):upper()
	if #s < 6 or #s > 16 then return nil end
	return s
end

function _cfgShare.pull(input)
	local code = _cfgShare.parseCode(input)
	if not code then return nil, "Paste a config code or a share link." end

	local res, err = _cfgShare.request("GET", _cfgShare.baseUrl .. "/c/" .. code)
	if not res then return nil, err end
	-- Le worker garde le PlaceId d'origine : on refuse ici plutôt que de
	-- laisser LoadConfiguration échouer plus loin sur un message obscur.
	if tostring(res.place_id) ~= tostring(game.PlaceId) then
		return nil, "This config was made for another game."
	end
	if type(res.config) ~= "table" or type(res.config.flags) ~= "table" then
		return nil, "This config is empty or corrupt."
	end
	res.code = res.code or code
	return res
end

-- Sauvegarde le slot donné (ou CActiveSlot) avec snapshot complet des flags.
-- Si le fichier existe déjà il est écrasé (clear + write).
local function SaveConfiguration(slotName)
	if not CEnabled then return end
	if not _hasFS then return end
	slotName = slotName or CActiveSlot
	if not slotName or slotName == "" then
		warn("RayVoid | SaveConfiguration: no active slot.")
		return
	end
	if not CPlaceFolder then return end

	local flags = _cfgShare.snapshot()

	local payload = HttpService:JSONEncode({
		placeId = game.PlaceId,
		flags   = flags,
	})

	-- Les dossiers sont garantis par FILESYSTEM INIT — on écrit directement
	local path = CPlaceFolder .. "/" .. slotName .. ConfigurationExtension
	callSafely(writefile, path, payload)

	CActiveSlot = slotName
	_saveMeta()

	if debugX then warn("RayVoid | SaveConfiguration → " .. path) end
end

function RayfieldLibrary:Notify(data) -- action e.g open messages
	data = data or {}
	-- Pendant la restauration d'une config, les callbacks rejoués peuvent spammer
	-- des notifs ("flag X chargé"). On les avale, sauf si l'appel est marqué Force
	-- (utilisé par RayVoid pour la notif finale "Name chargé").
	if _suppressNotify and not data.Force then return end
	task.spawn(function()

		-- Notification Object Creation
		local newNotification = Notifications.Template:Clone()
		newNotification.Name = data.Title or 'No Title Provided'
		newNotification.Parent = Notifications
		newNotification.LayoutOrder = #Notifications:GetChildren()
		newNotification.Visible = false

		-- Set Data
		newNotification.Title.Text = data.Title or "Unknown Title"
		newNotification.Description.Text = data.Content or "Unknown Content"

		if data.Image then
			local img, rectOffset, rectSize = resolveIcon(data.Image)
			newNotification.Icon.Image = img
			if rectOffset then newNotification.Icon.ImageRectOffset = rectOffset end
			if rectSize then newNotification.Icon.ImageRectSize = rectSize end
		else
			newNotification.Icon.Image = ""
		end

		-- Set initial transparency values

		newNotification.Title.TextColor3 = SelectedTheme.TextColor
		newNotification.Description.TextColor3 = SelectedTheme.TextColor
		newNotification.BackgroundColor3 = SelectedTheme.Background
		newNotification.UIStroke.Color = SelectedTheme.TextColor
		newNotification.Icon.ImageColor3 = SelectedTheme.TextColor

		newNotification.BackgroundTransparency = 1
		newNotification.Title.TextTransparency = 1
		newNotification.Description.TextTransparency = 1
		newNotification.UIStroke.Transparency = 1
		newNotification.Shadow.ImageTransparency = 1
		newNotification.Size = UDim2.new(1, 0, 0, 800)
		newNotification.Icon.ImageTransparency = 1
		newNotification.Icon.BackgroundTransparency = 1

		task.wait()

		newNotification.Visible = true

		if data.Actions then
			warn('Rayfield | Not seeing your actions in notifications?')
			print("Notification Actions are being sunset for now, keep up to date on when they're back in the discord. (sirius.menu/discord)")
		end

		-- Calculate textbounds and set initial values
		local bounds = {newNotification.Title.TextBounds.Y, newNotification.Description.TextBounds.Y}
		newNotification.Size = UDim2.new(1, -60, 0, -Notifications:FindFirstChild("UIListLayout").Padding.Offset)

		newNotification.Icon.Size = UDim2.new(0, 32, 0, 32)
		newNotification.Icon.Position = UDim2.new(0, 20, 0.5, 0)

		TweenService:Create(newNotification, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, 0, 0, math.max(bounds[1] + bounds[2] + 31, 60))}):Play()

		task.wait(0.15)
		TweenService:Create(newNotification, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.45}):Play()
		TweenService:Create(newNotification.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

		task.wait(0.05)

		TweenService:Create(newNotification.Icon, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()

		task.wait(0.05)
		TweenService:Create(newNotification.Description, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0.35}):Play()
		TweenService:Create(newNotification.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Transparency = 0.95}):Play()
		TweenService:Create(newNotification.Shadow, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0.82}):Play()

		local waitDuration = math.min(math.max((#newNotification.Description.Text * 0.1) + 2.5, 3), 10)
		task.wait(data.Duration or waitDuration)

		newNotification.Icon.Visible = false
		TweenService:Create(newNotification, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
		TweenService:Create(newNotification.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
		TweenService:Create(newNotification.Shadow, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
		TweenService:Create(newNotification.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
		TweenService:Create(newNotification.Description, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()

		TweenService:Create(newNotification, TweenInfo.new(1, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -90, 0, 0)}):Play()

		task.wait(1)

		TweenService:Create(newNotification, TweenInfo.new(1, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -90, 0, -Notifications:FindFirstChild("UIListLayout").Padding.Offset)}):Play()

		newNotification.Visible = false
		newNotification:Destroy()
	end)
end

local function openSearch()
	searchOpen = true

	Main.Search.BackgroundTransparency = 1
	Main.Search.Shadow.ImageTransparency = 1
	Main.Search.Input.TextTransparency = 1
	Main.Search.Search.ImageTransparency = 1
	Main.Search.UIStroke.Transparency = 1
	Main.Search.Size = UDim2.new(1, 0, 0, 80)
	Main.Search.Position = UDim2.new(0.5, 0, 0, 70)

	Main.Search.Input.Interactable = true

	Main.Search.Visible = true

	for _, tabbtn in ipairs(TabList:GetChildren()) do
		if tabbtn.ClassName == "Frame" and tabbtn.Name ~= "Placeholder" then
			tabbtn.Interact.Visible = false
			TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
			TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
			TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
			TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
		end
	end

	Main.Search.Input:CaptureFocus()
	TweenService:Create(Main.Search.Shadow, TweenInfo.new(0.05, Enum.EasingStyle.Quint), {ImageTransparency = 0.95}):Play()
	TweenService:Create(Main.Search, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Position = UDim2.new(0.5, 0, 0, 57), BackgroundTransparency = 0.9}):Play()
	TweenService:Create(Main.Search.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.8}):Play()
	TweenService:Create(Main.Search.Input, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
	TweenService:Create(Main.Search.Search, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0.5}):Play()
	TweenService:Create(Main.Search, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -35, 0, 35)}):Play()
end

local function closeSearch()
	searchOpen = false

	TweenService:Create(Main.Search, TweenInfo.new(0.35, Enum.EasingStyle.Quint), {BackgroundTransparency = 1, Size = UDim2.new(1, -55, 0, 30)}):Play()
	TweenService:Create(Main.Search.Search, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {ImageTransparency = 1}):Play()
	TweenService:Create(Main.Search.Shadow, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {ImageTransparency = 1}):Play()
	TweenService:Create(Main.Search.UIStroke, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {Transparency = 1}):Play()
	TweenService:Create(Main.Search.Input, TweenInfo.new(0.15, Enum.EasingStyle.Quint), {TextTransparency = 1}):Play()

	for _, tabbtn in ipairs(TabList:GetChildren()) do
		if tabbtn.ClassName == "Frame" and tabbtn.Name ~= "Placeholder" then
			tabbtn.Interact.Visible = true
			if tostring(Elements.UIPageLayout.CurrentPage) == tabbtn.Title.Text then
				TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
				TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
				TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
				TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
			else
				TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
				TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
				TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
				TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
			end
		end
	end

	Main.Search.Input.Text = ''
	Main.Search.Input.Interactable = false
end

-- Sets element visibility across all tab pages (used by Hide, Unhide, Maximise, Minimise)
local function setElementsVisible(show)
	for _, tab in ipairs(Elements:GetChildren()) do
		if tab.Name ~= "Template" and tab.ClassName == "ScrollingFrame" and tab.Name ~= "Placeholder" then
			for _, element in ipairs(tab:GetChildren()) do
				if element.ClassName == "Frame" then
					if element.Name ~= "SectionSpacing" and element.Name ~= "Placeholder" then
						if element.Name == "SectionTitle" or element.Name == 'SearchTitle-fsefsefesfsefesfesfThanks' then
							TweenService:Create(element.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = show and 0.4 or 1}):Play()
						elseif element.Name == 'Divider' then
							TweenService:Create(element.Divider, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = show and 0.85 or 1}):Play()
						else
							local bgTarget = element:GetAttribute("BackgroundTransparencyTarget") or 0
							local strokeTarget = element:GetAttribute("UIStrokeTransparencyTarget") or 0
							local titleTarget = element:GetAttribute("TitleTextTransparencyTarget") or 0
							TweenService:Create(element, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = show and bgTarget or 1}):Play()
							local stroke = element:FindFirstChildOfClass("UIStroke")
							if stroke then
								TweenService:Create(stroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = show and strokeTarget or 1}):Play()
							end
							local title = element:FindFirstChild("Title")
							if title then
								TweenService:Create(title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = show and titleTarget or 1}):Play()
							end
						end
						for _, child in ipairs(element:GetChildren()) do
							if child.ClassName == "Frame" or child.ClassName == "TextLabel" or child.ClassName == "TextBox" or child.ClassName == "ImageButton" or child.ClassName == "ImageLabel" then
								child.Visible = show
								if child.ClassName == "Frame" then
									local childStroke = child:FindFirstChildOfClass("UIStroke")
									if childStroke then
										TweenService:Create(childStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = show and 0 or 1}):Play()
									end
								end
							end
						end
					end
				end
			end
		end
	end
end

-- Sets tab button visibility (used by Hide, Unhide, Maximise, Minimise)
local function setTabButtonsVisible(show)
	for _, tabbtn in ipairs(TabList:GetChildren()) do
		if tabbtn.ClassName == "Frame" and tabbtn.Name ~= "Placeholder" then
			if show then
				if tostring(Elements.UIPageLayout.CurrentPage) == tabbtn.Title.Text then
					TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
					TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
					TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
					TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
				else
					TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
					TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
					TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
					TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				end
			else
				TweenService:Create(tabbtn, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
				TweenService:Create(tabbtn.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
				TweenService:Create(tabbtn.Image, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
				TweenService:Create(tabbtn.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
			end
		end
	end
end

local function Hide(notify: boolean?)
	if MPrompt then
		MPrompt.Title.TextColor3 = Color3.fromRGB(255, 255, 255)
		MPrompt.Position = UDim2.new(0.5, 0, 0, -50)
		MPrompt.Size = UDim2.new(0, 40, 0, 10)
		MPrompt.BackgroundTransparency = 1
		MPrompt.Title.TextTransparency = 1
		MPrompt.Visible = true
	end

	task.spawn(closeSearch)

	Debounce = true
	if notify then
		if useMobilePrompt then 
			RayfieldLibrary:Notify({Title = "Interface Hidden", Content = "The interface has been hidden, you can unhide the interface by tapping 'Show'.", Duration = 7, Image = 4400697855})
		else
			RayfieldLibrary:Notify({Title = "Interface Hidden", Content = "The interface has been hidden, you can unhide the interface by tapping " .. tostring(toggleKeybind) .. ".", Duration = 7, Image = 4400697855})
		end
	end

	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 470, 0, 0)}):Play()
	TweenService:Create(Main.Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 470, 0, 45)}):Play()
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main.Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main.Topbar.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main.Topbar.CornerRepair, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
	TweenService:Create(Topbar.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
	if dragBarCosmetic then
		TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	end

	if useMobilePrompt and MPrompt then
		TweenService:Create(MPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 120, 0, 30), Position = UDim2.new(0.5, 0, 0, 20), BackgroundTransparency = 0.3}):Play()
		TweenService:Create(MPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0.3}):Play()
	end

	for _, TopbarButton in ipairs(Topbar:GetChildren()) do
		if TopbarButton.ClassName == "ImageButton" then
			TweenService:Create(TopbarButton, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
		end
	end

	setTabButtonsVisible(false)

	if dragInteract then dragInteract.Visible = false end

	setElementsVisible(false)

	task.wait(0.5)
	Main.Visible = false
	Debounce = false
	_showReopenBtn()
end

local function Maximise()
	Debounce = true
	Topbar.ChangeSize.Image = customAssets[tostring(10137941941)]

	TweenService:Create(Topbar.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 0.6}):Play()
	TweenService:Create(Topbar.CornerRepair, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Topbar.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	if dragBarCosmetic then  -- FIX: nil-check
		TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.7}):Play()
	end
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = useMobileSizing and UDim2.new(0, 500, 0, 275) or UDim2.new(0, 500, 0, 475)}):Play()
	TweenService:Create(Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 500, 0, 45)}):Play()
	TabList.Visible = true
	task.wait(0.2)

	Elements.Visible = true

	setElementsVisible(true)

	task.wait(0.1)

	setTabButtonsVisible(true)

	task.wait(0.5)
	Debounce = false
end


local function Unhide()
	Debounce = true
	_hideReopenBtn()
	Main.Visible = true
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = useMobileSizing and UDim2.new(0, 500, 0, 275) or UDim2.new(0, 500, 0, 475)}):Play()
	TweenService:Create(Main.Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 500, 0, 45)}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.6}):Play()
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Topbar.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Topbar.CornerRepair, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Topbar.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

	if MPrompt then
		TweenService:Create(MPrompt, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 40, 0, 10), Position = UDim2.new(0.5, 0, 0, -50), BackgroundTransparency = 1}):Play()
		TweenService:Create(MPrompt.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()

		task.spawn(function()
			task.wait(0.5)
			MPrompt.Visible = false
		end)
	end

	if Minimised then
		task.spawn(Maximise)
	end

	if dragInteract then dragInteract.Visible = true end

	for _, TopbarButton in ipairs(Topbar:GetChildren()) do
		if TopbarButton.ClassName == "ImageButton" then
			if TopbarButton.Name == 'Icon' then
				TweenService:Create(TopbarButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
			else
				TweenService:Create(TopbarButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
			end

		end
	end

	setTabButtonsVisible(true)

	setElementsVisible(true)

	if dragBarCosmetic then  -- FIX: nil-check
		TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 0.5}):Play()
	end

	task.wait(0.5)
	Minimised = false
	Debounce = false
end

local function Minimise()
	Debounce = true
	Topbar.ChangeSize.Image = customAssets[tostring(11036884234)]

	Topbar.UIStroke.Color = SelectedTheme.ElementStroke

	task.spawn(closeSearch)

	setTabButtonsVisible(false)

	setElementsVisible(false)

	if dragBarCosmetic then  -- FIX: nil-check
		TweenService:Create(dragBarCosmetic, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {BackgroundTransparency = 1}):Play()
	end
	TweenService:Create(Topbar.UIStroke, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
	TweenService:Create(Topbar.CornerRepair, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Topbar.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
	TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 495, 0, 45)}):Play()
	TweenService:Create(Topbar, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 495, 0, 45)}):Play()

	task.wait(0.3)

	Elements.Visible = false
	TabList.Visible = false

	task.wait(0.2)
	Debounce = false
end





function RayfieldLibrary:CreateWindow(Settings)

	if getgenv then getgenv().rayfieldCached = true end

	if not correctBuild and not Settings.DisableBuildWarnings then
		task.delay(3, 
			function() 
				RayfieldLibrary:Notify({Title = 'Build Mismatch', Content = 'Rayfield may encounter issues as you are running an incompatible interface version ('.. ((Rayfield:FindFirstChild('Build') and Rayfield.Build.Value) or 'No Build') ..').\n\nThis version of Rayfield is intended for interface build '..InterfaceBuild..'.\n\nTry rejoining and then run the script twice.', Image = 4335487866, Duration = 15})		
			end)
	end

	if Settings.ToggleUIKeybind then -- Can either be a string or an Enum.KeyCode
		local keybind = Settings.ToggleUIKeybind
		if type(keybind) == "string" then
			keybind = string.upper(keybind)
			assert(pcall(function()
				return Enum.KeyCode[keybind]
			end), "ToggleUIKeybind must be a valid KeyCode")
			toggleKeybind = keybind
		elseif typeof(keybind) == "EnumItem" then
			assert(keybind.EnumType == Enum.KeyCode, "ToggleUIKeybind must be a KeyCode enum")
			toggleKeybind = keybind.Name
		else
			error("ToggleUIKeybind must be a string or KeyCode enum")
		end
	end

	-- ════════════════════════════════════════════════════════════════════
	--  SIDE TABS — active le mode sidebar gauche
	-- ════════════════════════════════════════════════════════════════════
	if Settings.SideTabs then
		_sideTabMode = true
	end

	ensureFolder(RayfieldFolder)

	-- ════════════════════════════════════════════════════════════════════
	--  FILESYSTEM INIT — toujours exécuté, indépendant de ConfigurationSaving
	--  Garantit que RAYVOID/ et RAYVOID/{PlaceId}/ existent avant tout
	-- ════════════════════════════════════════════════════════════════════

	_hasFS = type(makefolder) == "function"
	       and type(isfile) == "function"
	       and type(writefile) == "function"
	       and type(readfile) == "function"


	if _hasFS then
		-- 1. Dossier racine RAYVOID/
		local rayvoidExists = _isfolder(RAYVOID_BASE)
		if not rayvoidExists then
			local ok, err = pcall(makefolder, RAYVOID_BASE)
		end
		-- 2. Dossier du jeu courant RAYVOID/{PlaceId}/
		CPlaceFolder = RAYVOID_BASE .. "/" .. tostring(game.PlaceId)
		local placeExists = _isfolder(CPlaceFolder)
		if not placeExists then
			local ok, err = pcall(makefolder, CPlaceFolder)
		end
		-- 3. Fichier auto-load propre à ce jeu
		CAutoloadFile = CPlaceFolder .. "/autoload.json"
	else
	end

	_loadVoidPrefs()

	Main.Size = UDim2.new(0, 420, 0, 100)
	Main.Visible = true
	Main.BackgroundTransparency = 1
	if Main:FindFirstChild('Notice') then Main.Notice.Visible = false end
	Main.Shadow.Image.ImageTransparency = 1

	if Settings.ShowText then
		MPrompt.Title.Text = 'Show '..Settings.ShowText
	end

	-- FIX: Settings.Name n'était jamais appliqué à la topbar (contrairement à tous les
	-- autres composants qui font Component.Title.Text = ComponentSettings.Name)
	if Topbar:FindFirstChild('Title') then
		Topbar.Title.Text = Settings.Name or "Rayfield"
	end

	if Settings.LoadingTitle ~= "Rayfield Interface Suite" then
		LoadingFrame.Version.Text = "RayVoid"
	end

	if Settings.Icon and Settings.Icon ~= 0 and Topbar:FindFirstChild('Icon') then
		Topbar.Icon.Visible = true
		Topbar.Title.Position = UDim2.new(0, 47, 0.5, 0)

		if Settings.Icon then
			local img, rectOffset, rectSize = resolveIcon(Settings.Icon)
			Topbar.Icon.Image = img
			if rectOffset then Topbar.Icon.ImageRectOffset = rectOffset end
			if rectSize then Topbar.Icon.ImageRectSize = rectSize end
		else
			Topbar.Icon.Image = ""
		end
	end

	if dragBar then
		dragBar.Visible = false
		dragBarCosmetic.BackgroundTransparency = 1
		dragBar.Visible = true
	end

	if Settings.Theme then
		local success, result = pcall(ChangeTheme, Settings.Theme)
		if not success then
			local success, result2 = pcall(ChangeTheme, 'Default')
			if not success then
				warn('CRITICAL ERROR - NO DEFAULT THEME')
				print(result2)
			end
			warn('issue rendering theme. no theme on file')
			print(result)
		end
	end

	Topbar.Visible = false
	Elements.Visible = false
	LoadingFrame.Visible = true


	-- Lecture des settings ConfigurationSaving
	pcall(function()
		local cfgSave = Settings.ConfigurationSaving
		if type(cfgSave) ~= "table" then return end

		if cfgSave.Enabled == nil then
			cfgSave.Enabled = false
		end

		CEnabled = cfgSave.Enabled == true

		if CEnabled then
			-- Slot par défaut = FileName si fourni, sinon PlaceId en string
			if not cfgSave.FileName or cfgSave.FileName == "" then
				cfgSave.FileName = tostring(game.PlaceId)
			end
			CActiveSlot = cfgSave.FileName
		end
	end)

	-- autoload.json — lu toujours, indépendant de ConfigurationSaving
	-- CAutoloadFile est garanti set par le bloc FILESYSTEM INIT ci-dessus
	if _hasFS then
		_loadMeta()
	end


	makeDraggable(Main, Topbar, false, {dragOffset, dragOffsetMobile})
	if dragBar then dragBar.Position = useMobileSizing and UDim2.new(0.5, 0, 0.5, dragOffsetMobile) or UDim2.new(0.5, 0, 0.5, dragOffset) makeDraggable(Main, dragInteract, true, {dragOffset, dragOffsetMobile}) end

	for _, TabButton in ipairs(TabList:GetChildren()) do
		if TabButton.ClassName == "Frame" and TabButton.Name ~= "Placeholder" then
			TabButton.BackgroundTransparency = 1
			TabButton.Title.TextTransparency = 1
			TabButton.Image.ImageTransparency = 1
			TabButton.UIStroke.Transparency = 1
		end
	end


	Notifications.Template.Visible = false
	Notifications.Visible = true
	Rayfield.Enabled = true

	task.wait(0.1)
	TweenService:Create(Main, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.6}):Play()

	Elements.Template.LayoutOrder = 100000
	Elements.Template.Visible = false

	Elements.UIPageLayout.FillDirection = Enum.FillDirection.Horizontal
	Elements.UIPageLayout.ScrollWheelInputEnabled = false
	Elements.UIPageLayout.GamepadInputEnabled = false
	Elements.UIPageLayout.TouchInputEnabled = false
	TabList.Template.Visible = false

	-- Tab
	local FirstTab = false
	local Window = {}
	function Window:CreateTab(Name, Image, Ext)
		local SDone = false
		local TabButton = TabList.Template:Clone()
		TabButton.Name = Name
		TabButton.Title.Text = Name
		TabButton.Parent = TabList
		TabButton.Title.TextWrapped = false
		-- ════════════════════════════════════════════════════════════════
		--  SIDE TAB MODE — sizing adapté à la sidebar verticale
		-- ════════════════════════════════════════════════════════════════
		if _sideTabMode then
			TabButton.Size                 = UDim2.new(1, -8, 0, 36)
			TabButton.Title.TextWrapped    = true
			TabButton.Title.Position       = UDim2.new(0, 10, 0.5, 0)
			TabButton.Title.AnchorPoint    = Vector2.new(0, 0.5)
			TabButton.Title.TextXAlignment = Enum.TextXAlignment.Left
		else
			TabButton.Size = UDim2.new(0, TabButton.Title.TextBounds.X + 30, 0, 30)
		end

		if Image and Image ~= 0 then
			local img, rectOffset, rectSize = resolveIcon(Image)
			TabButton.Image.Image = img
			if rectOffset then TabButton.Image.ImageRectOffset = rectOffset end
			if rectSize then TabButton.Image.ImageRectSize = rectSize end

			TabButton.Title.AnchorPoint    = Vector2.new(0, 0.5)
			TabButton.Title.Position       = UDim2.new(0, 37, 0.5, 0)
			TabButton.Image.Visible        = true
			TabButton.Title.TextXAlignment = Enum.TextXAlignment.Left
			if not _sideTabMode then
				TabButton.Size = UDim2.new(0, TabButton.Title.TextBounds.X + 52, 0, 30)
			end
		end



		TabButton.BackgroundTransparency = 1
		TabButton.Title.TextTransparency = 1
		TabButton.Image.ImageTransparency = 1
		TabButton.UIStroke.Transparency = 1

		TabButton.Visible = not Ext or false

		-- Create Elements Page
		local TabPage = Elements.Template:Clone()
		TabPage.Name = Name
		TabPage.Visible = true

		TabPage.LayoutOrder = Ext and 10000 or #Elements:GetChildren()

		for _, TemplateElement in ipairs(TabPage:GetChildren()) do
			if TemplateElement.ClassName == "Frame" and TemplateElement.Name ~= "Placeholder" then
				TemplateElement:Destroy()
			end
		end

		TabPage.Parent = Elements
		if not FirstTab and not Ext then
			Elements.UIPageLayout.Animated = false
			Elements.UIPageLayout:JumpTo(TabPage)
			Elements.UIPageLayout.Animated = true
		end

		TabButton.UIStroke.Color = SelectedTheme.TabStroke

		if Elements.UIPageLayout.CurrentPage == TabPage then
			TabButton.BackgroundColor3 = SelectedTheme.TabBackgroundSelected
			TabButton.Image.ImageColor3 = SelectedTheme.SelectedTabTextColor
			TabButton.Title.TextColor3 = SelectedTheme.SelectedTabTextColor
		else
			TabButton.BackgroundColor3 = SelectedTheme.TabBackground
			TabButton.Image.ImageColor3 = SelectedTheme.TabTextColor
			TabButton.Title.TextColor3 = SelectedTheme.TabTextColor
		end


		-- Animate
		task.wait(0.1)
		if FirstTab or Ext then
			TabButton.BackgroundColor3 = SelectedTheme.TabBackground
			TabButton.Image.ImageColor3 = SelectedTheme.TabTextColor
			TabButton.Title.TextColor3 = SelectedTheme.TabTextColor
			TweenService:Create(TabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
			TweenService:Create(TabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
			TweenService:Create(TabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
			TweenService:Create(TabButton.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
		elseif not Ext then
			FirstTab = Name
			TabButton.BackgroundColor3 = SelectedTheme.TabBackgroundSelected
			TabButton.Image.ImageColor3 = SelectedTheme.SelectedTabTextColor
			TabButton.Title.TextColor3 = SelectedTheme.SelectedTabTextColor
			TweenService:Create(TabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
			TweenService:Create(TabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(TabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
		end


		TabButton.Interact.MouseButton1Click:Connect(function()
			if Minimised then return end
			TweenService:Create(TabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(TabButton.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
			TweenService:Create(TabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			TweenService:Create(TabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
			TweenService:Create(TabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.TabBackgroundSelected}):Play()
			TweenService:Create(TabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextColor3 = SelectedTheme.SelectedTabTextColor}):Play()
			TweenService:Create(TabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageColor3 = SelectedTheme.SelectedTabTextColor}):Play()

			for _, OtherTabButton in ipairs(TabList:GetChildren()) do
				if OtherTabButton.Name ~= "Template" and OtherTabButton.ClassName == "Frame" and OtherTabButton ~= TabButton and OtherTabButton.Name ~= "Placeholder" then
					TweenService:Create(OtherTabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.TabBackground}):Play()
					TweenService:Create(OtherTabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextColor3 = SelectedTheme.TabTextColor}):Play()
					TweenService:Create(OtherTabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageColor3 = SelectedTheme.TabTextColor}):Play()
					TweenService:Create(OtherTabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
					TweenService:Create(OtherTabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
					TweenService:Create(OtherTabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
					TweenService:Create(OtherTabButton.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
				end
			end

			if Elements.UIPageLayout.CurrentPage ~= TabPage then
				Elements.UIPageLayout:JumpTo(TabPage)
			end
		end)

		local Tab = {}

		-- Vide tous les éléments du tab (utile pour les tabs reconstruits dynamiquement)
		function Tab:Clear()
			for _, child in ipairs(TabPage:GetChildren()) do
				if child.ClassName == "Frame" and child.Name ~= "Placeholder" then
					child:Destroy()
				end
			end
		end

		-- Button
		function Tab:CreateButton(ButtonSettings)
			local ButtonValue = {}

			local Button = Elements.Template.Button:Clone()
			Button.Name = ButtonSettings.Name
			Button.Title.Text = ButtonSettings.Name
			Button.Visible = true
			Button.Parent = TabPage

			Button.BackgroundTransparency = 1
			Button.UIStroke.Transparency = 1
			Button.Title.TextTransparency = 1

			TweenService:Create(Button, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Button.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Button.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	


			Button.Interact.MouseButton1Click:Connect(function()
				local Success, Response = pcall(ButtonSettings.Callback)
				-- Prevents animation from trying to play if the button's callback called RayfieldLibrary:Destroy()
				if rayfieldDestroyed then
					return
				end
				if not Success then
					TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Button.Title.Text = "Callback Error"
					print("Rayfield | "..ButtonSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Button.Title.Text = ButtonSettings.Name
					TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0.9}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				else
					if not ButtonSettings.Ext then
						-- plus d'auto-save ici : save explicite uniquement via le Settings tab
					end
					TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					task.wait(0.2)
					TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0.9}):Play()
					TweenService:Create(Button.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end
			end)

			Button.MouseEnter:Connect(function()
				TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
				TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0.7}):Play()
			end)

			Button.MouseLeave:Connect(function()
				TweenService:Create(Button, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
				TweenService:Create(Button.ElementIndicator, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0.9}):Play()
			end)

			function ButtonValue:Set(NewButton)
				Button.Title.Text = NewButton
				Button.Name = NewButton
			end

			return ButtonValue
		end

		-- ColorPicker
		function Tab:CreateColorPicker(ColorPickerSettings) -- by Throit
			ColorPickerSettings.Type = "ColorPicker"
			local ColorPicker = Elements.Template.ColorPicker:Clone()
			local Background = ColorPicker.CPBackground
			local Display = Background.Display
			local Main = Background.MainCP
			local Slider = ColorPicker.ColorSlider
			ColorPicker.ClipsDescendants = true
			ColorPicker.Name = ColorPickerSettings.Name
			ColorPicker.Title.Text = ColorPickerSettings.Name
			ColorPicker.Visible = true
			ColorPicker.Parent = TabPage
			ColorPicker.Size = UDim2.new(1, -10, 0, 45)
			Background.Size = UDim2.new(0, 39, 0, 22)
			Display.BackgroundTransparency = 0
			Main.MainPoint.ImageTransparency = 1
			ColorPicker.Interact.Size = UDim2.new(1, 0, 1, 0)
			ColorPicker.Interact.Position = UDim2.new(0.5, 0, 0.5, 0)
			ColorPicker.RGB.Position = UDim2.new(0, 17, 0, 70)
			ColorPicker.HexInput.Position = UDim2.new(0, 17, 0, 90)
			Main.ImageTransparency = 1
			Background.BackgroundTransparency = 1

			for _, rgbinput in ipairs(ColorPicker.RGB:GetChildren()) do
				if rgbinput:IsA("Frame") then
					rgbinput.BackgroundColor3 = SelectedTheme.InputBackground
					rgbinput.UIStroke.Color = SelectedTheme.InputStroke
				end
			end

			ColorPicker.HexInput.BackgroundColor3 = SelectedTheme.InputBackground
			ColorPicker.HexInput.UIStroke.Color = SelectedTheme.InputStroke

			local opened = false 
			local mouse = Players.LocalPlayer:GetMouse()
			local mainDragging = false 
			local sliderDragging = false 
			ColorPicker.Interact.MouseButton1Down:Connect(function()
				task.spawn(function()
					TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(ColorPicker.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					task.wait(0.2)
					TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(ColorPicker.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end)

				if not opened then
					opened = true 
					TweenService:Create(Background, TweenInfo.new(0.45, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 18, 0, 15)}):Play()
					task.wait(0.1)
					TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 120)}):Play()
					TweenService:Create(Background, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 173, 0, 86)}):Play()
					TweenService:Create(Display, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
					TweenService:Create(ColorPicker.Interact, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Position = UDim2.new(0.289, 0, 0.5, 0)}):Play()
					TweenService:Create(ColorPicker.RGB, TweenInfo.new(0.8, Enum.EasingStyle.Exponential), {Position = UDim2.new(0, 17, 0, 40)}):Play()
					TweenService:Create(ColorPicker.HexInput, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Position = UDim2.new(0, 17, 0, 73)}):Play()
					TweenService:Create(ColorPicker.Interact, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0.574, 0, 1, 0)}):Play()
					TweenService:Create(Main.MainPoint, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
					TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {ImageTransparency = SelectedTheme ~= RayfieldLibrary.Theme.Default and 0.25 or 0.1}):Play()
					TweenService:Create(Background, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
				else
					opened = false
					TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 45)}):Play()
					TweenService:Create(Background, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(0, 39, 0, 22)}):Play()
					TweenService:Create(ColorPicker.Interact, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, 0, 1, 0)}):Play()
					TweenService:Create(ColorPicker.Interact, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Position = UDim2.new(0.5, 0, 0.5, 0)}):Play()
					TweenService:Create(ColorPicker.RGB, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Position = UDim2.new(0, 17, 0, 70)}):Play()
					TweenService:Create(ColorPicker.HexInput, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Position = UDim2.new(0, 17, 0, 90)}):Play()
					TweenService:Create(Display, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
					TweenService:Create(Main.MainPoint, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
					TweenService:Create(Main, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {ImageTransparency = 1}):Play()
					TweenService:Create(Background, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
				end

			end)

			local colorPickerInputConnection = UserInputService.InputEnded:Connect(function(input, gameProcessed) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
					mainDragging = false
					sliderDragging = false
				end end)
			Main.MouseButton1Down:Connect(function()
				if opened then
					mainDragging = true 
				end
			end)
			Main.MainPoint.MouseButton1Down:Connect(function()
				if opened then
					mainDragging = true 
				end
			end)
			Slider.MouseButton1Down:Connect(function()
				sliderDragging = true 
			end)
			Slider.SliderPoint.MouseButton1Down:Connect(function()
				sliderDragging = true 
			end)
			local h,s,v = ColorPickerSettings.Color:ToHSV()
			local color = Color3.fromHSV(h,s,v) 
			local hex = string.format("#%02X%02X%02X",color.R*0xFF,color.G*0xFF,color.B*0xFF)
			ColorPicker.HexInput.InputBox.Text = hex
			local function setDisplay()
				--Main
				Main.MainPoint.Position = UDim2.new(s,-Main.MainPoint.AbsoluteSize.X/2,1-v,-Main.MainPoint.AbsoluteSize.Y/2)
				Main.MainPoint.ImageColor3 = Color3.fromHSV(h,s,v)
				Background.BackgroundColor3 = Color3.fromHSV(h,1,1)
				Display.BackgroundColor3 = Color3.fromHSV(h,s,v)
				--Slider 
				local x = h * Slider.AbsoluteSize.X
				Slider.SliderPoint.Position = UDim2.new(0,x-Slider.SliderPoint.AbsoluteSize.X/2,0.5,0)
				Slider.SliderPoint.ImageColor3 = Color3.fromHSV(h,1,1)
				local color = Color3.fromHSV(h,s,v) 
				local r,g,b = math.floor((color.R*255)+0.5),math.floor((color.G*255)+0.5),math.floor((color.B*255)+0.5)
				ColorPicker.RGB.RInput.InputBox.Text = tostring(r)
				ColorPicker.RGB.GInput.InputBox.Text = tostring(g)
				ColorPicker.RGB.BInput.InputBox.Text = tostring(b)
				hex = string.format("#%02X%02X%02X",color.R*0xFF,color.G*0xFF,color.B*0xFF)
				ColorPicker.HexInput.InputBox.Text = hex
			end
			setDisplay()
			ColorPicker.HexInput.InputBox.FocusLost:Connect(function()
				if not pcall(function()
						local r, g, b = string.match(ColorPicker.HexInput.InputBox.Text, "^#?(%w%w)(%w%w)(%w%w)$")
						local rgbColor = Color3.fromRGB(tonumber(r, 16),tonumber(g, 16), tonumber(b, 16))
						h,s,v = rgbColor:ToHSV()
						hex = ColorPicker.HexInput.InputBox.Text
						setDisplay()
						ColorPickerSettings.Color = rgbColor
					end) 
				then 
					ColorPicker.HexInput.InputBox.Text = hex 
				end
				pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
				local r,g,b = math.floor((h*255)+0.5),math.floor((s*255)+0.5),math.floor((v*255)+0.5)
				ColorPickerSettings.Color = Color3.fromRGB(r,g,b)
				if not ColorPickerSettings.Ext then
				end
			end)
			--RGB
			local function rgbBoxes(box,toChange)
				local value = tonumber(box.Text) 
				local color = Color3.fromHSV(h,s,v) 
				local oldR,oldG,oldB = math.floor((color.R*255)+0.5),math.floor((color.G*255)+0.5),math.floor((color.B*255)+0.5)
				local save 
				if toChange == "R" then save = oldR;oldR = value elseif toChange == "G" then save = oldG;oldG = value else save = oldB;oldB = value end
				if value then 
					value = math.clamp(value,0,255)
					h,s,v = Color3.fromRGB(oldR,oldG,oldB):ToHSV()

					setDisplay()
				else 
					box.Text = tostring(save)
				end
				local r,g,b = math.floor((h*255)+0.5),math.floor((s*255)+0.5),math.floor((v*255)+0.5)
				ColorPickerSettings.Color = Color3.fromRGB(r,g,b)
			end
			ColorPicker.RGB.RInput.InputBox.FocusLost:connect(function()
				rgbBoxes(ColorPicker.RGB.RInput.InputBox,"R")
				pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
			end)
			ColorPicker.RGB.GInput.InputBox.FocusLost:connect(function()
				rgbBoxes(ColorPicker.RGB.GInput.InputBox,"G")
				pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
			end)
			ColorPicker.RGB.BInput.InputBox.FocusLost:connect(function()
				rgbBoxes(ColorPicker.RGB.BInput.InputBox,"B")
				pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
			end)

			local colorPickerRenderConnection = RunService.RenderStepped:connect(function()
				if mainDragging then
					local localX = math.clamp(mouse.X-Main.AbsolutePosition.X,0,Main.AbsoluteSize.X)
					local localY = math.clamp(mouse.Y-Main.AbsolutePosition.Y,0,Main.AbsoluteSize.Y)
					Main.MainPoint.Position = UDim2.new(0,localX-Main.MainPoint.AbsoluteSize.X/2,0,localY-Main.MainPoint.AbsoluteSize.Y/2)
					s = localX / Main.AbsoluteSize.X
					v = 1 - (localY / Main.AbsoluteSize.Y)
					Display.BackgroundColor3 = Color3.fromHSV(h,s,v)
					Main.MainPoint.ImageColor3 = Color3.fromHSV(h,s,v)
					Background.BackgroundColor3 = Color3.fromHSV(h,1,1)
					local color = Color3.fromHSV(h,s,v) 
					local r,g,b = math.floor((color.R*255)+0.5),math.floor((color.G*255)+0.5),math.floor((color.B*255)+0.5)
					ColorPicker.RGB.RInput.InputBox.Text = tostring(r)
					ColorPicker.RGB.GInput.InputBox.Text = tostring(g)
					ColorPicker.RGB.BInput.InputBox.Text = tostring(b)
					ColorPicker.HexInput.InputBox.Text = string.format("#%02X%02X%02X",color.R*0xFF,color.G*0xFF,color.B*0xFF)
					pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
					ColorPickerSettings.Color = Color3.fromRGB(r,g,b)
					if not ColorPickerSettings.Ext then
					end
				end
				if sliderDragging then 
					local localX = math.clamp(mouse.X-Slider.AbsolutePosition.X,0,Slider.AbsoluteSize.X)
					h = localX / Slider.AbsoluteSize.X
					Display.BackgroundColor3 = Color3.fromHSV(h,s,v)
					Slider.SliderPoint.Position = UDim2.new(0,localX-Slider.SliderPoint.AbsoluteSize.X/2,0.5,0)
					Slider.SliderPoint.ImageColor3 = Color3.fromHSV(h,1,1)
					Background.BackgroundColor3 = Color3.fromHSV(h,1,1)
					Main.MainPoint.ImageColor3 = Color3.fromHSV(h,s,v)
					local color = Color3.fromHSV(h,s,v) 
					local r,g,b = math.floor((color.R*255)+0.5),math.floor((color.G*255)+0.5),math.floor((color.B*255)+0.5)
					ColorPicker.RGB.RInput.InputBox.Text = tostring(r)
					ColorPicker.RGB.GInput.InputBox.Text = tostring(g)
					ColorPicker.RGB.BInput.InputBox.Text = tostring(b)
					ColorPicker.HexInput.InputBox.Text = string.format("#%02X%02X%02X",color.R*0xFF,color.G*0xFF,color.B*0xFF)
					pcall(function()ColorPickerSettings.Callback(Color3.fromHSV(h,s,v))end)
					ColorPickerSettings.Color = Color3.fromRGB(r,g,b)
					if not ColorPickerSettings.Ext then
					end
				end
			end)

			ColorPicker.Destroying:Connect(function()
				if colorPickerRenderConnection then
					colorPickerRenderConnection:Disconnect()
				end
				if colorPickerInputConnection then
					colorPickerInputConnection:Disconnect()
				end
			end)

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and ColorPickerSettings.Flag then
					RayfieldLibrary.Flags[ColorPickerSettings.Flag] = ColorPickerSettings
					_onComponentCreated()
				end
			end

			function ColorPickerSettings:Set(RGBColor)
				ColorPickerSettings.Color = RGBColor
				h,s,v = ColorPickerSettings.Color:ToHSV()
				color = Color3.fromHSV(h,s,v)
				setDisplay()
			end

			ColorPicker.MouseEnter:Connect(function()
				TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			ColorPicker.MouseLeave:Connect(function()
				TweenService:Create(ColorPicker, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				for _, rgbinput in ipairs(ColorPicker.RGB:GetChildren()) do
					if rgbinput:IsA("Frame") then
						rgbinput.BackgroundColor3 = SelectedTheme.InputBackground
						rgbinput.UIStroke.Color = SelectedTheme.InputStroke
					end
				end

				ColorPicker.HexInput.BackgroundColor3 = SelectedTheme.InputBackground
				ColorPicker.HexInput.UIStroke.Color = SelectedTheme.InputStroke
			end)

			return ColorPickerSettings
		end

		-- Section
		function Tab:CreateSection(SectionName)

			local SectionValue = {}

			if SDone then
				local SectionSpace = Elements.Template.SectionSpacing:Clone()
				SectionSpace.Visible = true
				SectionSpace.Parent = TabPage
			end

			local Section = Elements.Template.SectionTitle:Clone()
			Section.Title.Text = SectionName
			Section.Visible = true
			Section.Parent = TabPage

			Section.Title.TextTransparency = 1
			TweenService:Create(Section.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0.4}):Play()

			function SectionValue:Set(NewSection)
				Section.Title.Text = NewSection
			end

			SDone = true

			return SectionValue
		end

		-- Divider
		function Tab:CreateDivider()
			local DividerValue = {}

			local Divider = Elements.Template.Divider:Clone()
			Divider.Visible = true
			Divider.Parent = TabPage

			Divider.Divider.BackgroundTransparency = 1
			TweenService:Create(Divider.Divider, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.85}):Play()

			function DividerValue:Set(Value)
				Divider.Visible = Value
			end

			return DividerValue
		end

		-- Label
		function Tab:CreateLabel(LabelText : string, Icon: number, Color : Color3, IgnoreTheme : boolean)
			local LabelValue = {}

			local Label = Elements.Template.Label:Clone()
			Label.Title.Text = LabelText
			Label.Visible = true
			Label.Parent = TabPage

			Label.BackgroundColor3 = Color or SelectedTheme.SecondaryElementBackground
			Label.UIStroke.Color = Color or SelectedTheme.SecondaryElementStroke

			if Icon then
				local img, rectOffset, rectSize = resolveIcon(Icon)
				Label.Icon.Image = img
				if rectOffset then Label.Icon.ImageRectOffset = rectOffset end
				if rectSize then Label.Icon.ImageRectSize = rectSize end
			else
				Label.Icon.Image = ""
			end

			if Icon and Label:FindFirstChild('Icon') then
				Label.Title.Position = UDim2.new(0, 45, 0.5, 0)
				Label.Title.Size = UDim2.new(1, -100, 0, 14)
				Label.Icon.Visible = true
			end

			Label.Icon.ImageTransparency = 1
			Label.BackgroundTransparency = 1
			Label.UIStroke.Transparency = 1
			Label.Title.TextTransparency = 1

			Label:SetAttribute("BackgroundTransparencyTarget", Color and 0.8 or 0)
			Label:SetAttribute("UIStrokeTransparencyTarget", Color and 0.7 or 0)
			Label:SetAttribute("TitleTextTransparencyTarget", Color and 0.2 or 0)

			TweenService:Create(Label, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = Color and 0.8 or 0}):Play()
			TweenService:Create(Label.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = Color and 0.7 or 0}):Play()
			TweenService:Create(Label.Icon, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
			TweenService:Create(Label.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = Color and 0.2 or 0}):Play()

			function LabelValue:Set(NewLabel, Icon, Color)
				Label.Title.Text = NewLabel

				if Color then
					Label.BackgroundColor3 = Color or SelectedTheme.SecondaryElementBackground
					Label.UIStroke.Color = Color or SelectedTheme.SecondaryElementStroke
				end

				if Icon and Label:FindFirstChild('Icon') then
					Label.Title.Position = UDim2.new(0, 45, 0.5, 0)
					Label.Title.Size = UDim2.new(1, -100, 0, 14)

					local img, rectOffset, rectSize = resolveIcon(Icon)
					Label.Icon.Image = img
					if rectOffset then Label.Icon.ImageRectOffset = rectOffset end
					if rectSize then Label.Icon.ImageRectSize = rectSize end

					Label.Icon.Visible = true
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Label.BackgroundColor3 = IgnoreTheme and (Color or Label.BackgroundColor3) or SelectedTheme.SecondaryElementBackground
				Label.UIStroke.Color = IgnoreTheme and (Color or Label.BackgroundColor3) or SelectedTheme.SecondaryElementStroke
			end)

			return LabelValue
		end

		-- Paragraph
		function Tab:CreateParagraph(ParagraphSettings)
			local ParagraphValue = {}

			local Paragraph = Elements.Template.Paragraph:Clone()
			Paragraph.Title.Text = ParagraphSettings.Title
			Paragraph.Content.Text = ParagraphSettings.Content
			Paragraph.Visible = true
			Paragraph.Parent = TabPage

			Paragraph.BackgroundTransparency = 1
			Paragraph.UIStroke.Transparency = 1
			Paragraph.Title.TextTransparency = 1
			Paragraph.Content.TextTransparency = 1

			Paragraph.BackgroundColor3 = SelectedTheme.SecondaryElementBackground
			Paragraph.UIStroke.Color = SelectedTheme.SecondaryElementStroke

			TweenService:Create(Paragraph, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Paragraph.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Paragraph.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	
			TweenService:Create(Paragraph.Content, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			function ParagraphValue:Set(NewParagraphSettings)
				Paragraph.Title.Text = NewParagraphSettings.Title
				Paragraph.Content.Text = NewParagraphSettings.Content
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Paragraph.BackgroundColor3 = SelectedTheme.SecondaryElementBackground
				Paragraph.UIStroke.Color = SelectedTheme.SecondaryElementStroke
			end)

			return ParagraphValue
		end

		-- Rich Paragraph — comme CreateParagraph mais RichText activé (balises <font>,
		-- <b>, <i>...) + couleur de bordure/accent optionnelle (cfg.Color).
		function Tab:CreateRichParagraph(ParagraphSettings)
			local ParagraphValue = {}

			local Paragraph = Elements.Template.Paragraph:Clone()
			Paragraph.Title.RichText   = true
			Paragraph.Content.RichText = true
			Paragraph.Title.Text   = ParagraphSettings.Title or ""
			Paragraph.Content.Text = ParagraphSettings.Content or ""
			Paragraph.Visible = true
			Paragraph.Parent = TabPage

			Paragraph.BackgroundTransparency = 1
			Paragraph.UIStroke.Transparency = 1
			Paragraph.Title.TextTransparency = 1
			Paragraph.Content.TextTransparency = 1

			local accent = ParagraphSettings.Color
			Paragraph.BackgroundColor3 = SelectedTheme.SecondaryElementBackground
			Paragraph.UIStroke.Color = accent or SelectedTheme.SecondaryElementStroke
			if accent then Paragraph.UIStroke.Thickness = 1 end

			TweenService:Create(Paragraph, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Paragraph.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = accent and 0.2 or 0}):Play()
			TweenService:Create(Paragraph.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
			TweenService:Create(Paragraph.Content, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()

			function ParagraphValue:Set(NewParagraphSettings)
				Paragraph.Title.Text = NewParagraphSettings.Title or Paragraph.Title.Text
				Paragraph.Content.Text = NewParagraphSettings.Content or Paragraph.Content.Text
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Paragraph.BackgroundColor3 = SelectedTheme.SecondaryElementBackground
				if not accent then Paragraph.UIStroke.Color = SelectedTheme.SecondaryElementStroke end
			end)

			return ParagraphValue
		end

		-- Input
		function Tab:CreateInput(InputSettings)
			local Input = Elements.Template.Input:Clone()
			Input.Name = InputSettings.Name
			Input.Title.Text = InputSettings.Name
			Input.Visible = true
			Input.Parent = TabPage

			Input.BackgroundTransparency = 1
			Input.UIStroke.Transparency = 1
			Input.Title.TextTransparency = 1

			Input.InputFrame.InputBox.Text = InputSettings.CurrentValue or ''

			Input.InputFrame.BackgroundColor3 = SelectedTheme.InputBackground
			Input.InputFrame.UIStroke.Color = SelectedTheme.InputStroke

			TweenService:Create(Input, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Input.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Input.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			Input.InputFrame.InputBox.PlaceholderText = InputSettings.PlaceholderText
			Input.InputFrame.Size = UDim2.new(0, Input.InputFrame.InputBox.TextBounds.X + 24, 0, 30)

			Input.InputFrame.InputBox.FocusLost:Connect(function()
				local Success, Response = pcall(function()
					InputSettings.Callback(Input.InputFrame.InputBox.Text)
					InputSettings.CurrentValue = Input.InputFrame.InputBox.Text
				end)

				if not Success then
					TweenService:Create(Input, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Input.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Input.Title.Text = "Callback Error"
					print("Rayfield | "..InputSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Input.Title.Text = InputSettings.Name
					TweenService:Create(Input, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Input.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				if InputSettings.RemoveTextAfterFocusLost then
					Input.InputFrame.InputBox.Text = ""
				end

				if not InputSettings.Ext then
				end
			end)

			Input.MouseEnter:Connect(function()
				TweenService:Create(Input, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			Input.MouseLeave:Connect(function()
				TweenService:Create(Input, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			Input.InputFrame.InputBox:GetPropertyChangedSignal("Text"):Connect(function()
				TweenService:Create(Input.InputFrame, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Input.InputFrame.InputBox.TextBounds.X + 24, 0, 30)}):Play()
			end)

			function InputSettings:Set(text)
				Input.InputFrame.InputBox.Text = text
				InputSettings.CurrentValue = text

				local Success, Response = pcall(function()
					InputSettings.Callback(text)
				end)

				if not InputSettings.Ext then
				end
			end

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and InputSettings.Flag then
					RayfieldLibrary.Flags[InputSettings.Flag] = InputSettings
					_onComponentCreated()
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Input.InputFrame.BackgroundColor3 = SelectedTheme.InputBackground
				Input.InputFrame.UIStroke.Color = SelectedTheme.InputStroke
			end)

			return InputSettings
		end

		-- Dropdown
		function Tab:CreateDropdown(DropdownSettings)
			local Dropdown = Elements.Template.Dropdown:Clone()
			if string.find(DropdownSettings.Name,"closed") then
				Dropdown.Name = "Dropdown"
			else
				Dropdown.Name = DropdownSettings.Name
			end
			Dropdown.Title.Text = DropdownSettings.Name
			Dropdown.Visible = true
			Dropdown.Parent = TabPage

			Dropdown.List.Visible = false
			if DropdownSettings.CurrentOption then
				if type(DropdownSettings.CurrentOption) == "string" then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption}
				end
				if not DropdownSettings.MultipleOptions and type(DropdownSettings.CurrentOption) == "table" then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption[1]}
				end
			else
				DropdownSettings.CurrentOption = {}
			end

			if DropdownSettings.MultipleOptions then
				if DropdownSettings.CurrentOption and type(DropdownSettings.CurrentOption) == "table" then
					if #DropdownSettings.CurrentOption == 1 then
						Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
					elseif #DropdownSettings.CurrentOption == 0 then
						Dropdown.Selected.Text = "None"
					else
						Dropdown.Selected.Text = "Various"
					end
				else
					DropdownSettings.CurrentOption = {}
					Dropdown.Selected.Text = "None"
				end
			else
				Dropdown.Selected.Text = DropdownSettings.CurrentOption[1] or "None"
			end

			Dropdown.Toggle.ImageColor3 = SelectedTheme.TextColor
			TweenService:Create(Dropdown, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()

			Dropdown.BackgroundTransparency = 1
			Dropdown.UIStroke.Transparency = 1
			Dropdown.Title.TextTransparency = 1

			Dropdown.Size = UDim2.new(1, -10, 0, 45)

			TweenService:Create(Dropdown, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Dropdown.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			for _, ununusedoption in ipairs(Dropdown.List:GetChildren()) do
				if ununusedoption.ClassName == "Frame" and ununusedoption.Name ~= "Placeholder" then
					ununusedoption:Destroy()
				end
			end

			Dropdown.Toggle.Rotation = 180

			Dropdown.Interact.MouseButton1Click:Connect(function()
				TweenService:Create(Dropdown, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
				TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
				task.wait(0.1)
				TweenService:Create(Dropdown, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
				TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				if Debounce then return end
				if Dropdown.List.Visible then
					Debounce = true
					TweenService:Create(Dropdown, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 45)}):Play()
					for _, DropdownOpt in ipairs(Dropdown.List:GetChildren()) do
						if DropdownOpt.ClassName == "Frame" and DropdownOpt.Name ~= "Placeholder" then
							TweenService:Create(DropdownOpt, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
							TweenService:Create(DropdownOpt.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
							TweenService:Create(DropdownOpt.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
						end
					end
					TweenService:Create(Dropdown.List, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ScrollBarImageTransparency = 1}):Play()
					TweenService:Create(Dropdown.Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Rotation = 180}):Play()	
					task.wait(0.35)
					Dropdown.List.Visible = false
					Debounce = false
				else
					TweenService:Create(Dropdown, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 180)}):Play()
					Dropdown.List.Visible = true
					TweenService:Create(Dropdown.List, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ScrollBarImageTransparency = 0.7}):Play()
					TweenService:Create(Dropdown.Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Rotation = 0}):Play()	
					for _, DropdownOpt in ipairs(Dropdown.List:GetChildren()) do
						if DropdownOpt.ClassName == "Frame" and DropdownOpt.Name ~= "Placeholder" then
							if DropdownOpt.Name ~= Dropdown.Selected.Text then
								TweenService:Create(DropdownOpt.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
							end
							TweenService:Create(DropdownOpt, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
							TweenService:Create(DropdownOpt.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
						end
					end
				end
			end)

			Dropdown.MouseEnter:Connect(function()
				if not Dropdown.List.Visible then
					TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
				end
			end)

			Dropdown.MouseLeave:Connect(function()
				TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			local function SetDropdownOptions()
				for _, Option in ipairs(DropdownSettings.Options) do
					local DropdownOption = Elements.Template.Dropdown.List.Template:Clone()
					DropdownOption.Name = Option
					DropdownOption.Title.Text = Option
					DropdownOption.Parent = Dropdown.List
					DropdownOption.Visible = true

					DropdownOption.BackgroundTransparency = 1
					DropdownOption.UIStroke.Transparency = 1
					DropdownOption.Title.TextTransparency = 1

					--local Dropdown = Tab:CreateDropdown({
					--	Name = "Dropdown Example",
					--	Options = {"Option 1","Option 2"},
					--	CurrentOption = {"Option 1"},
					--  MultipleOptions = true,
					--	Flag = "Dropdown1",
					--	Callback = function(TableOfOptions)

					--	end,
					--})


					DropdownOption.Interact.ZIndex = 50
					DropdownOption.Interact.MouseButton1Click:Connect(function()
						if not DropdownSettings.MultipleOptions and table.find(DropdownSettings.CurrentOption, Option) then 
							return
						end

						if table.find(DropdownSettings.CurrentOption, Option) then
							table.remove(DropdownSettings.CurrentOption, table.find(DropdownSettings.CurrentOption, Option))
							if DropdownSettings.MultipleOptions then
								if #DropdownSettings.CurrentOption == 1 then
									Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
								elseif #DropdownSettings.CurrentOption == 0 then
									Dropdown.Selected.Text = "None"
								else
									Dropdown.Selected.Text = "Various"
								end
							else
								Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
							end
						else
							if not DropdownSettings.MultipleOptions then
								table.clear(DropdownSettings.CurrentOption)
							end
							table.insert(DropdownSettings.CurrentOption, Option)
							if DropdownSettings.MultipleOptions then
								if #DropdownSettings.CurrentOption == 1 then
									Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
								elseif #DropdownSettings.CurrentOption == 0 then
									Dropdown.Selected.Text = "None"
								else
									Dropdown.Selected.Text = "Various"
								end
							else
								Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
							end
							TweenService:Create(DropdownOption.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
							TweenService:Create(DropdownOption, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.DropdownSelected}):Play()
							Debounce = true
						end


						local Success, Response = pcall(function()
							DropdownSettings.Callback(DropdownSettings.CurrentOption)
						end)

						if not Success then
							TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
							TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
							Dropdown.Title.Text = "Callback Error"
							print("Rayfield | "..DropdownSettings.Name.." Callback Error " ..tostring(Response))
							warn('Check docs.sirius.menu for help with Rayfield specific development.')
							task.wait(0.5)
							Dropdown.Title.Text = DropdownSettings.Name
							TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
							TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
						end

						for _, droption in ipairs(Dropdown.List:GetChildren()) do
							if droption.ClassName == "Frame" and droption.Name ~= "Placeholder" and not table.find(DropdownSettings.CurrentOption, droption.Name) then
								TweenService:Create(droption, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.DropdownUnselected}):Play()
							end
						end
						if not DropdownSettings.MultipleOptions then
							task.wait(0.1)
							TweenService:Create(Dropdown, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, -10, 0, 45)}):Play()
							for _, DropdownOpt in ipairs(Dropdown.List:GetChildren()) do
								if DropdownOpt.ClassName == "Frame" and DropdownOpt.Name ~= "Placeholder" then
									TweenService:Create(DropdownOpt, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {BackgroundTransparency = 1}):Play()
									TweenService:Create(DropdownOpt.UIStroke, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
									TweenService:Create(DropdownOpt.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
								end
							end
							TweenService:Create(Dropdown.List, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ScrollBarImageTransparency = 1}):Play()
							TweenService:Create(Dropdown.Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Rotation = 180}):Play()	
							task.wait(0.35)
							Dropdown.List.Visible = false
						end
						Debounce = false
						if not DropdownSettings.Ext then
						end
					end)

					Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
						DropdownOption.UIStroke.Color = SelectedTheme.ElementStroke
					end)
				end
			end
			SetDropdownOptions()

			for _, droption in ipairs(Dropdown.List:GetChildren()) do
				if droption.ClassName == "Frame" and droption.Name ~= "Placeholder" then
					if not table.find(DropdownSettings.CurrentOption, droption.Name) then
						droption.BackgroundColor3 = SelectedTheme.DropdownUnselected
					else
						droption.BackgroundColor3 = SelectedTheme.DropdownSelected
					end

					Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
						if not table.find(DropdownSettings.CurrentOption, droption.Name) then
							droption.BackgroundColor3 = SelectedTheme.DropdownUnselected
						else
							droption.BackgroundColor3 = SelectedTheme.DropdownSelected
						end
					end)
				end
			end

			function DropdownSettings:Set(NewOption)
				DropdownSettings.CurrentOption = NewOption

				if typeof(DropdownSettings.CurrentOption) == "string" then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption}
				end

				if not DropdownSettings.MultipleOptions then
					DropdownSettings.CurrentOption = {DropdownSettings.CurrentOption[1]}
				end

				if DropdownSettings.MultipleOptions then
					if #DropdownSettings.CurrentOption == 1 then
						Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
					elseif #DropdownSettings.CurrentOption == 0 then
						Dropdown.Selected.Text = "None"
					else
						Dropdown.Selected.Text = "Various"
					end
				else
					Dropdown.Selected.Text = DropdownSettings.CurrentOption[1]
				end


				local Success, Response = pcall(function()
					DropdownSettings.Callback(NewOption)
				end)
				if not Success then
					TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Dropdown.Title.Text = "Callback Error"
					print("Rayfield | "..DropdownSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Dropdown.Title.Text = DropdownSettings.Name
					TweenService:Create(Dropdown, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Dropdown.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				for _, droption in ipairs(Dropdown.List:GetChildren()) do
					if droption.ClassName == "Frame" and droption.Name ~= "Placeholder" then
						if not table.find(DropdownSettings.CurrentOption, droption.Name) then
							droption.BackgroundColor3 = SelectedTheme.DropdownUnselected
						else
							droption.BackgroundColor3 = SelectedTheme.DropdownSelected
						end
					end
				end
				--SaveConfiguration()
			end

			function DropdownSettings:Refresh(optionsTable: table) -- updates a dropdown with new options from optionsTable
				DropdownSettings.Options = optionsTable
				for _, option in Dropdown.List:GetChildren() do
					if option.ClassName == "Frame" and option.Name ~= "Placeholder" then
						option:Destroy()
					end
				end
				SetDropdownOptions()

				-- Apply selected/unselected background colors to new options
				for _, droption in ipairs(Dropdown.List:GetChildren()) do
					if droption.ClassName == "Frame" and droption.Name ~= "Placeholder" then
						if not table.find(DropdownSettings.CurrentOption, droption.Name) then
							droption.BackgroundColor3 = SelectedTheme.DropdownUnselected
						else
							droption.BackgroundColor3 = SelectedTheme.DropdownSelected
						end
					end
				end

				-- If the dropdown is currently open, make new options visible immediately
				if Dropdown.List.Visible then
					for _, DropdownOpt in ipairs(Dropdown.List:GetChildren()) do
						if DropdownOpt.ClassName == "Frame" and DropdownOpt.Name ~= "Placeholder" then
							DropdownOpt.BackgroundTransparency = 0
							DropdownOpt.Title.TextTransparency = 0
							if not table.find(DropdownSettings.CurrentOption, DropdownOpt.Name) then
								DropdownOpt.UIStroke.Transparency = 0
							end
						end
					end
				end
			end

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and DropdownSettings.Flag then
					RayfieldLibrary.Flags[DropdownSettings.Flag] = DropdownSettings
					_onComponentCreated()
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Dropdown.Toggle.ImageColor3 = SelectedTheme.TextColor
				TweenService:Create(Dropdown, TweenInfo.new(0.4, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			return DropdownSettings
		end

		-- Keybind
		function Tab:CreateKeybind(KeybindSettings)
			local CheckingForKey = false
			local Keybind = Elements.Template.Keybind:Clone()
			Keybind.Name = KeybindSettings.Name
			Keybind.Title.Text = KeybindSettings.Name
			Keybind.Visible = true
			Keybind.Parent = TabPage

			Keybind.BackgroundTransparency = 1
			Keybind.UIStroke.Transparency = 1
			Keybind.Title.TextTransparency = 1

			Keybind.KeybindFrame.BackgroundColor3 = SelectedTheme.InputBackground
			Keybind.KeybindFrame.UIStroke.Color = SelectedTheme.InputStroke

			TweenService:Create(Keybind, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Keybind.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Keybind.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			Keybind.KeybindFrame.KeybindBox.Text = KeybindSettings.CurrentKeybind
			Keybind.KeybindFrame.Size = UDim2.new(0, Keybind.KeybindFrame.KeybindBox.TextBounds.X + 24, 0, 30)

			Keybind.KeybindFrame.KeybindBox.Focused:Connect(function()
				CheckingForKey = true
				Keybind.KeybindFrame.KeybindBox.Text = ""
			end)
			Keybind.KeybindFrame.KeybindBox.FocusLost:Connect(function()
				CheckingForKey = false
				if Keybind.KeybindFrame.KeybindBox.Text == nil or Keybind.KeybindFrame.KeybindBox.Text == "" then
					Keybind.KeybindFrame.KeybindBox.Text = KeybindSettings.CurrentKeybind
					if not KeybindSettings.Ext then
					end
				end
			end)

			Keybind.MouseEnter:Connect(function()
				TweenService:Create(Keybind, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			Keybind.MouseLeave:Connect(function()
				TweenService:Create(Keybind, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			local connection = UserInputService.InputBegan:Connect(function(input, processed)
				if CheckingForKey then
					if input.KeyCode ~= Enum.KeyCode.Unknown then
						local SplitMessage = string.split(tostring(input.KeyCode), ".")
						local NewKeyNoEnum = SplitMessage[3]
						Keybind.KeybindFrame.KeybindBox.Text = tostring(NewKeyNoEnum)
						KeybindSettings.CurrentKeybind = tostring(NewKeyNoEnum)
						Keybind.KeybindFrame.KeybindBox:ReleaseFocus()
						if not KeybindSettings.Ext then
						end

						if KeybindSettings.CallOnChange then
							KeybindSettings.Callback(tostring(NewKeyNoEnum))
						end
					end
				elseif not KeybindSettings.CallOnChange and KeybindSettings.CurrentKeybind ~= nil and (input.KeyCode == Enum.KeyCode[KeybindSettings.CurrentKeybind] and not processed) then -- Test
					local Held = true
					local Connection
					Connection = input.Changed:Connect(function(prop)
						if prop == "UserInputState" then
							Connection:Disconnect()
							Held = false
						end
					end)

					if not KeybindSettings.HoldToInteract then
						local Success, Response = pcall(KeybindSettings.Callback)
						if not Success then
							TweenService:Create(Keybind, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
							TweenService:Create(Keybind.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
							Keybind.Title.Text = "Callback Error"
							print("Rayfield | "..KeybindSettings.Name.." Callback Error " ..tostring(Response))
							warn('Check docs.sirius.menu for help with Rayfield specific development.')
							task.wait(0.5)
							Keybind.Title.Text = KeybindSettings.Name
							TweenService:Create(Keybind, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
							TweenService:Create(Keybind.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
						end
					else
						task.wait(0.25)
						if Held then
							local Loop; Loop = RunService.Stepped:Connect(function()
								if not Held then
									KeybindSettings.Callback(false) -- maybe pcall this
									Loop:Disconnect()
								else
									KeybindSettings.Callback(true) -- maybe pcall this
								end
							end)
						end
					end
				end
			end)
			table.insert(keybindConnections, connection)

			Keybind.KeybindFrame.KeybindBox:GetPropertyChangedSignal("Text"):Connect(function()
				TweenService:Create(Keybind.KeybindFrame, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Keybind.KeybindFrame.KeybindBox.TextBounds.X + 24, 0, 30)}):Play()
			end)

			function KeybindSettings:Set(NewKeybind)
				Keybind.KeybindFrame.KeybindBox.Text = tostring(NewKeybind)
				KeybindSettings.CurrentKeybind = tostring(NewKeybind)
				Keybind.KeybindFrame.KeybindBox:ReleaseFocus()
				if not KeybindSettings.Ext then
				end

				if KeybindSettings.CallOnChange then
					KeybindSettings.Callback(tostring(NewKeybind))
				end
			end

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and KeybindSettings.Flag then
					RayfieldLibrary.Flags[KeybindSettings.Flag] = KeybindSettings
					_onComponentCreated()
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Keybind.KeybindFrame.BackgroundColor3 = SelectedTheme.InputBackground
				Keybind.KeybindFrame.UIStroke.Color = SelectedTheme.InputStroke
			end)

			return KeybindSettings
		end

		-- Toggle
		function Tab:CreateToggle(ToggleSettings)
			local ToggleValue = {}

			local Toggle = Elements.Template.Toggle:Clone()
			Toggle.Name = ToggleSettings.Name
			Toggle.Title.Text = ToggleSettings.Name
			Toggle.Visible = true
			Toggle.Parent = TabPage

			Toggle.BackgroundTransparency = 1
			Toggle.UIStroke.Transparency = 1
			Toggle.Title.TextTransparency = 1
			Toggle.Switch.BackgroundColor3 = SelectedTheme.ToggleBackground

			if SelectedTheme ~= RayfieldLibrary.Theme.Default then
				Toggle.Switch.Shadow.Visible = false
			end

			TweenService:Create(Toggle, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Toggle.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			if ToggleSettings.CurrentValue == true then
				Toggle.Switch.Indicator.Position = UDim2.new(1, -20, 0.5, 0)
				Toggle.Switch.Indicator.UIStroke.Color = SelectedTheme.ToggleEnabledStroke
				Toggle.Switch.Indicator.BackgroundColor3 = SelectedTheme.ToggleEnabled
				Toggle.Switch.UIStroke.Color = SelectedTheme.ToggleEnabledOuterStroke
			else
				Toggle.Switch.Indicator.Position = UDim2.new(1, -40, 0.5, 0)
				Toggle.Switch.Indicator.UIStroke.Color = SelectedTheme.ToggleDisabledStroke
				Toggle.Switch.Indicator.BackgroundColor3 = SelectedTheme.ToggleDisabled
				Toggle.Switch.UIStroke.Color = SelectedTheme.ToggleDisabledOuterStroke
			end

			Toggle.MouseEnter:Connect(function()
				TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			Toggle.MouseLeave:Connect(function()
				TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			Toggle.Interact.MouseButton1Click:Connect(function()
				if ToggleSettings.CurrentValue == true then
					ToggleSettings.CurrentValue = false
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(1, -40, 0.5, 0)}):Play()
					TweenService:Create(Toggle.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleDisabledStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundColor3 = SelectedTheme.ToggleDisabled}):Play()
					TweenService:Create(Toggle.Switch.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleDisabledOuterStroke}):Play()
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()	
				else
					ToggleSettings.CurrentValue = true
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(1, -20, 0.5, 0)}):Play()
					TweenService:Create(Toggle.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleEnabledStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundColor3 = SelectedTheme.ToggleEnabled}):Play()
					TweenService:Create(Toggle.Switch.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleEnabledOuterStroke}):Play()
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()		
				end

				local Success, Response = pcall(function()
					if debugX then warn('Running toggle \''..ToggleSettings.Name..'\' (Interact)') end

					ToggleSettings.Callback(ToggleSettings.CurrentValue)
				end)

				if not Success then
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Toggle.Title.Text = "Callback Error"
					print("Rayfield | "..ToggleSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Toggle.Title.Text = ToggleSettings.Name
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				if not ToggleSettings.Ext then
				end
			end)

			function ToggleSettings:Set(NewToggleValue)
				if NewToggleValue == true then
					ToggleSettings.CurrentValue = true
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(1, -20, 0.5, 0)}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0,12,0,12)}):Play()
					TweenService:Create(Toggle.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleEnabledStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundColor3 = SelectedTheme.ToggleEnabled}):Play()
					TweenService:Create(Toggle.Switch.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleEnabledOuterStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0,17,0,17)}):Play()	
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()	
				else
					ToggleSettings.CurrentValue = false
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Position = UDim2.new(1, -40, 0.5, 0)}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0,12,0,12)}):Play()
					TweenService:Create(Toggle.Switch.Indicator.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleDisabledStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.8, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {BackgroundColor3 = SelectedTheme.ToggleDisabled}):Play()
					TweenService:Create(Toggle.Switch.UIStroke, TweenInfo.new(0.55, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Color = SelectedTheme.ToggleDisabledOuterStroke}):Play()
					TweenService:Create(Toggle.Switch.Indicator, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {Size = UDim2.new(0,17,0,17)}):Play()
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()	
				end

				local Success, Response = pcall(function()
					if debugX then warn('Running toggle \''..ToggleSettings.Name..'\' (:Set)') end

					ToggleSettings.Callback(ToggleSettings.CurrentValue)
				end)

				if not Success then
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Toggle.Title.Text = "Callback Error"
					print("Rayfield | "..ToggleSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Toggle.Title.Text = ToggleSettings.Name
					TweenService:Create(Toggle, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Toggle.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				if not ToggleSettings.Ext then
				end
			end

			if not ToggleSettings.Ext then
				if Settings.ConfigurationSaving then
					if Settings.ConfigurationSaving.Enabled and ToggleSettings.Flag then
						RayfieldLibrary.Flags[ToggleSettings.Flag] = ToggleSettings
						_onComponentCreated()
					end
				end
			end


			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				Toggle.Switch.BackgroundColor3 = SelectedTheme.ToggleBackground

				if SelectedTheme ~= RayfieldLibrary.Theme.Default then
					Toggle.Switch.Shadow.Visible = false
				end

				task.wait()

				if not ToggleSettings.CurrentValue then
					Toggle.Switch.Indicator.UIStroke.Color = SelectedTheme.ToggleDisabledStroke
					Toggle.Switch.Indicator.BackgroundColor3 = SelectedTheme.ToggleDisabled
					Toggle.Switch.UIStroke.Color = SelectedTheme.ToggleDisabledOuterStroke
				else
					Toggle.Switch.Indicator.UIStroke.Color = SelectedTheme.ToggleEnabledStroke
					Toggle.Switch.Indicator.BackgroundColor3 = SelectedTheme.ToggleEnabled
					Toggle.Switch.UIStroke.Color = SelectedTheme.ToggleEnabledOuterStroke
				end
			end)

			return ToggleSettings
		end

		-- Slider
		function Tab:CreateSlider(SliderSettings)
			local SLDragging = false
			local Slider = Elements.Template.Slider:Clone()
			Slider.Name = SliderSettings.Name
			Slider.Title.Text = SliderSettings.Name
			Slider.Visible = true
			Slider.Parent = TabPage

			Slider.BackgroundTransparency = 1
			Slider.UIStroke.Transparency = 1
			Slider.Title.TextTransparency = 1

			if SelectedTheme ~= RayfieldLibrary.Theme.Default then
				Slider.Main.Shadow.Visible = false
			end

			Slider.Main.BackgroundColor3 = SelectedTheme.SliderBackground
			Slider.Main.UIStroke.Color = SelectedTheme.SliderStroke
			Slider.Main.Progress.UIStroke.Color = SelectedTheme.SliderStroke
			Slider.Main.Progress.BackgroundColor3 = SelectedTheme.SliderProgress

			TweenService:Create(Slider, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
			TweenService:Create(Slider.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
			TweenService:Create(Slider.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()	

			Slider.Main.Progress.Size =	UDim2.new(0, Slider.Main.AbsoluteSize.X * ((SliderSettings.CurrentValue - SliderSettings.Range[1]) / (SliderSettings.Range[2] - SliderSettings.Range[1])) > 5 and Slider.Main.AbsoluteSize.X * ((SliderSettings.CurrentValue - SliderSettings.Range[1]) / (SliderSettings.Range[2] - SliderSettings.Range[1])) or 5, 1, 0)

			if not SliderSettings.Suffix then
				Slider.Main.Information.Text = tostring(SliderSettings.CurrentValue)
			else
				Slider.Main.Information.Text = tostring(SliderSettings.CurrentValue) .. " " .. SliderSettings.Suffix
			end

			Slider.MouseEnter:Connect(function()
				TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackgroundHover}):Play()
			end)

			Slider.MouseLeave:Connect(function()
				TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
			end)

			Slider.Main.Interact.InputBegan:Connect(function(Input)
				if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then 
					TweenService:Create(Slider.Main.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					TweenService:Create(Slider.Main.Progress.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					SLDragging = true 
				end 
			end)

			Slider.Main.Interact.InputEnded:Connect(function(Input) 
				if Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch then 
					TweenService:Create(Slider.Main.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0.4}):Play()
					TweenService:Create(Slider.Main.Progress.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0.3}):Play()
					SLDragging = false 
				end 
			end)

			Slider.Main.Interact.MouseButton1Down:Connect(function(X)
				local Current = Slider.Main.Progress.AbsolutePosition.X + Slider.Main.Progress.AbsoluteSize.X
				local Start = Current
				local Location = X
				local Loop; Loop = RunService.Stepped:Connect(function()
					if SLDragging then
						Location = UserInputService:GetMouseLocation().X
						Current = Current + 0.025 * (Location - Start)

						if Location < Slider.Main.AbsolutePosition.X then
							Location = Slider.Main.AbsolutePosition.X
						elseif Location > Slider.Main.AbsolutePosition.X + Slider.Main.AbsoluteSize.X then
							Location = Slider.Main.AbsolutePosition.X + Slider.Main.AbsoluteSize.X
						end

						if Current < Slider.Main.AbsolutePosition.X + 5 then
							Current = Slider.Main.AbsolutePosition.X + 5
						elseif Current > Slider.Main.AbsolutePosition.X + Slider.Main.AbsoluteSize.X then
							Current = Slider.Main.AbsolutePosition.X + Slider.Main.AbsoluteSize.X
						end

						if Current <= Location and (Location - Start) < 0 then
							Start = Location
						elseif Current >= Location and (Location - Start) > 0 then
							Start = Location
						end
						TweenService:Create(Slider.Main.Progress, TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Current - Slider.Main.AbsolutePosition.X, 1, 0)}):Play()
						local NewValue = SliderSettings.Range[1] + (Location - Slider.Main.AbsolutePosition.X) / Slider.Main.AbsoluteSize.X * (SliderSettings.Range[2] - SliderSettings.Range[1])

						NewValue = math.floor(NewValue / SliderSettings.Increment + 0.5) * (SliderSettings.Increment * 10000000) / 10000000
						NewValue = math.clamp(NewValue, SliderSettings.Range[1], SliderSettings.Range[2])

						if not SliderSettings.Suffix then
							Slider.Main.Information.Text = tostring(NewValue)
						else
							Slider.Main.Information.Text = tostring(NewValue) .. " " .. SliderSettings.Suffix
						end

						if SliderSettings.CurrentValue ~= NewValue then
							local Success, Response = pcall(function()
								SliderSettings.Callback(NewValue)
							end)
							if not Success then
								TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
								TweenService:Create(Slider.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
								Slider.Title.Text = "Callback Error"
								print("Rayfield | "..SliderSettings.Name.." Callback Error " ..tostring(Response))
								warn('Check docs.sirius.menu for help with Rayfield specific development.')
								task.wait(0.5)
								Slider.Title.Text = SliderSettings.Name
								TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
								TweenService:Create(Slider.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
							end

							SliderSettings.CurrentValue = NewValue
							if not SliderSettings.Ext then
							end
						end
					else
						TweenService:Create(Slider.Main.Progress, TweenInfo.new(0.3, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Location - Slider.Main.AbsolutePosition.X > 5 and Location - Slider.Main.AbsolutePosition.X or 5, 1, 0)}):Play()
						Loop:Disconnect()
					end
				end)
			end)

			function SliderSettings:Set(NewVal)
				local NewVal = math.clamp(NewVal, SliderSettings.Range[1], SliderSettings.Range[2])

				TweenService:Create(Slider.Main.Progress, TweenInfo.new(0.45, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = UDim2.new(0, Slider.Main.AbsoluteSize.X * ((NewVal - SliderSettings.Range[1]) / (SliderSettings.Range[2] - SliderSettings.Range[1])) > 5 and Slider.Main.AbsoluteSize.X * ((NewVal - SliderSettings.Range[1]) / (SliderSettings.Range[2] - SliderSettings.Range[1])) or 5, 1, 0)}):Play()
				Slider.Main.Information.Text = tostring(NewVal) .. " " .. (SliderSettings.Suffix or "")

				local Success, Response = pcall(function()
					SliderSettings.Callback(NewVal)
				end)

				if not Success then
					TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = Color3.fromRGB(85, 0, 0)}):Play()
					TweenService:Create(Slider.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 1}):Play()
					Slider.Title.Text = "Callback Error"
					print("Rayfield | "..SliderSettings.Name.." Callback Error " ..tostring(Response))
					warn('Check docs.sirius.menu for help with Rayfield specific development.')
					task.wait(0.5)
					Slider.Title.Text = SliderSettings.Name
					TweenService:Create(Slider, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.ElementBackground}):Play()
					TweenService:Create(Slider.UIStroke, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {Transparency = 0}):Play()
				end

				SliderSettings.CurrentValue = NewVal
				if not SliderSettings.Ext then
				end
			end

			if Settings.ConfigurationSaving then
				if Settings.ConfigurationSaving.Enabled and SliderSettings.Flag then
					RayfieldLibrary.Flags[SliderSettings.Flag] = SliderSettings
					_onComponentCreated()
				end
			end

			Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
				if SelectedTheme ~= RayfieldLibrary.Theme.Default then
					Slider.Main.Shadow.Visible = false
				end

				Slider.Main.BackgroundColor3 = SelectedTheme.SliderBackground
				Slider.Main.UIStroke.Color = SelectedTheme.SliderStroke
				Slider.Main.Progress.UIStroke.Color = SelectedTheme.SliderStroke
				Slider.Main.Progress.BackgroundColor3 = SelectedTheme.SliderProgress
			end)

			return SliderSettings
		end

		Rayfield.Main:GetPropertyChangedSignal('BackgroundColor3'):Connect(function()
			TabButton.UIStroke.Color = SelectedTheme.TabStroke

			if Elements.UIPageLayout.CurrentPage == TabPage then
				TabButton.BackgroundColor3 = SelectedTheme.TabBackgroundSelected
				TabButton.Image.ImageColor3 = SelectedTheme.SelectedTabTextColor
				TabButton.Title.TextColor3 = SelectedTheme.SelectedTabTextColor
			else
				TabButton.BackgroundColor3 = SelectedTheme.TabBackground
				TabButton.Image.ImageColor3 = SelectedTheme.TabTextColor
				TabButton.Title.TextColor3 = SelectedTheme.TabTextColor
			end
		end)


		-- ── PROGRESS BAR — barre de progression non-interactive ──────────────────
		function Tab:CreateProgressBar(cfg)
			cfg = cfg or {}
			local maxVal = cfg.Max    or 100
			local curVal = math.clamp(cfg.Value or 0, 0, maxVal)
			local suffix = cfg.Suffix or ""

			local Container = Instance.new("Frame")
			Container.Name = "ProgressBar"
			Container.BackgroundColor3 = SelectedTheme.ElementBackground
			Container.Size = UDim2.new(1, 0, 0, 46)
			Container.Parent = TabPage
			VCorner(5, Container)
			VStroke(1, SelectedTheme.ElementStroke, Container)
			VMakeAccentBar(Container)

			VMakeLabel(Container, cfg.Label or "Progress",
				UDim2.new(1, -70, 0, 22),
				UDim2.new(0, 14, 0, 4),
				SelectedTheme.TextColor, 13, Enum.Font.GothamBold
			)

			local valLabel = VMakeLabel(Container,
				tostring(curVal) .. suffix,
				UDim2.new(0, 55, 0, 22),
				UDim2.new(1, -62, 0, 4),
				VC.Accent, 12, Enum.Font.GothamBold,
				Enum.TextXAlignment.Right
			)

			local track = VMakeFrame(Container,
				UDim2.new(1, -20, 0, 6),
				UDim2.new(0, 10, 1, -12),
				VC.BgDeep, 0
			)
			VCorner(3, track)

			local fill = VMakeFrame(track,
				UDim2.new(curVal / maxVal, 0, 1, 0),
				nil, VC.White, 0
			)
			VCorner(3, fill)
			VGradient(VC.Accent, VC.AccentPink, fill, 0)

			local progressObj = {
				Type = "ProgressBar",
				SetValue = function(_, v)
					v = math.clamp(v, 0, maxVal)
					curVal = v
					VTween(fill, { Size = UDim2.new(v / maxVal, 0, 1, 0) }, 0.3)
					valLabel.Text = tostring(v) .. suffix
				end,
				GetValue = function() return curVal end,
			}

			if cfg.Flag then
				RayfieldLibrary.Flags[cfg.Flag] = progressObj
				_onComponentCreated()
			end

			return progressObj
		end

		-- ── CARD GRID — grille de cards visuelles sélectionnables ────────────────
		function Tab:CreateCardGrid(cfg)
			cfg = cfg or {}
			local items    = cfg.Items    or {}
			local cols     = cfg.Columns  or 3
			local callback = cfg.Callback or function() end
			local selected = {}
			local cardSetters = {}  -- nom → SetCardSelected, pour SetSelected

			local cardH = 115
			local gap   = 8
			local rows   = math.ceil(#items / cols)
			local totalH = rows * (cardH + gap) + gap

			local Container = Instance.new("Frame")
			Container.Name = "CardGrid"
			Container.BackgroundTransparency = 1
			Container.Size = UDim2.new(1, 0, 0, totalH)
			Container:SetAttribute("BackgroundTransparencyTarget", 1)  -- FIX: évite le bug de couleur au minimize/maximize
			Container.Parent = TabPage

			local grid = VMakeFrame(Container, UDim2.new(1, 0, 1, 0), nil, VC.Black, 1)

			local gridLayout = Instance.new("UIGridLayout")
			gridLayout.CellSize      = UDim2.new(1/cols, -(gap * (cols + 1) / cols), 0, cardH)
			gridLayout.CellPadding   = UDim2.new(0, gap, 0, gap)
			gridLayout.SortOrder     = Enum.SortOrder.LayoutOrder
			gridLayout.FillDirection = Enum.FillDirection.Horizontal
			gridLayout.Parent        = grid
			VPad(gap, gap, gap, gap, grid)

			for i, item in ipairs(items) do
				local card = VMakeFrame(grid, UDim2.new(0, 1, 0, 1), nil, VC.BgMid, 0)
				card.LayoutOrder = i
				VCorner(10, card)
				local cardStroke = VStroke(1, VC.BorderDim, card)
				VGradient(VC.BgMid, VC.BgLight, card, 90)

				local img = Instance.new("ImageLabel")
				img.Size                   = UDim2.new(0.72, 0, 0, 68)
				img.Position               = UDim2.new(0.14, 0, 0, 7)
				img.BackgroundTransparency = 1
				img.Image                  = item.Icon or ""
				img.ScaleType              = Enum.ScaleType.Fit
				img.Parent                 = card

				local nameLabel = VMakeLabel(card,
					item.Name or "",
					UDim2.new(1, -6, 0, 18),
					UDim2.new(0, 3, 1, -22),
					VC.TextMid, 10, Enum.Font.GothamBold,
					Enum.TextXAlignment.Center
				)
				nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

				local checkBg = VMakeFrame(card,
					UDim2.new(0, 22, 0, 22),
					UDim2.new(1, -26, 0, 4),
					VC.Accent, 1
				)
				VCorner(11, checkBg)
				local checkLabel = VMakeLabel(checkBg, "✓",
					UDim2.new(1, 0, 1, 0), nil,
					VC.White, 12, Enum.Font.GothamBold,
					Enum.TextXAlignment.Center
				)
				checkLabel.TextYAlignment = Enum.TextYAlignment.Center

				local clickZone = Instance.new("TextButton")
				clickZone.Size                 = UDim2.new(1, 0, 1, 0)
				clickZone.BackgroundTransparency = 1
				clickZone.Text                 = ""
				clickZone.Parent               = card

				local isSelected = false

				local function SetCardSelected(v, silent)
					isSelected = v
					if v then
						selected[item.Name] = true
						VTween(cardStroke,  { Color = VC.Accent, Thickness = 2 },    0.2)
						VTween(card,        { BackgroundColor3 = VC.BgLighter },      0.2)
						VTween(checkBg,     { BackgroundTransparency = 0 },           0.2)
						VTween(nameLabel,   { TextColor3 = VC.TextBright },           0.2)
						VTween(img,         { ImageTransparency = 0 },                0.1)
					else
						selected[item.Name] = nil
						VTween(cardStroke,  { Color = VC.BorderDim, Thickness = 1 }, 0.2)
						VTween(card,        { BackgroundColor3 = VC.BgMid },          0.2)
						VTween(checkBg,     { BackgroundTransparency = 1 },           0.2)
						VTween(nameLabel,   { TextColor3 = VC.TextMid },              0.2)
					end
					if not silent then
						callback(selected)
					end
				end

				-- Stocke le setter pour SetSelected (restore config)
				cardSetters[item.Name] = SetCardSelected

				clickZone.MouseEnter:Connect(function()
					if not isSelected then
						VTween(card,       { BackgroundColor3 = VC.BgLight },  0.12)
						VTween(cardStroke, { Color = VC.AccentGlow },          0.12)
					end
				end)
				clickZone.MouseLeave:Connect(function()
					if not isSelected then
						VTween(card,       { BackgroundColor3 = VC.BgMid },    0.12)
						VTween(cardStroke, { Color = VC.BorderDim },           0.12)
					end
				end)
				clickZone.MouseButton1Click:Connect(function()
					SetCardSelected(not isSelected)
				end)

				-- Hook OnCardCreated — appelé après création de chaque card
				if cfg.OnCardCreated then
					task.spawn(function()
						cfg.OnCardCreated(item.Name, nameLabel)
					end)
				end
			end

			local cardObj = {
				Type = "CardGrid",
				GetSelected = function() return selected end,
				SetSelected = function(_, data)
					if type(data) ~= "table" then return end
					-- On applique visuellement chaque card puis on fire le callback une seule fois
					for _, item in ipairs(items) do
						local setter = cardSetters[item.Name]
						if setter then
							setter(data[item.Name] == true, true)  -- silent=true : pas de callback par card
						end
					end
					callback(selected)  -- callback unique après tout le restore
				end,
			}
			if cfg.Flag then
				RayfieldLibrary.Flags[cfg.Flag] = cardObj
				_onComponentCreated()
			end
			return cardObj
		end





		-- ── FILTERED CARD GRID — CardGrid avec filtre par groupe ─────────────────
		function Tab:CreateFilteredCardGrid(cfg)
			cfg = cfg or {}
			local groups   = cfg.Groups   or {}
			local cols     = cfg.Columns  or 4
			local callback = cfg.Callback or function() end

			local globalSelected = {}
			local groupIndex  = {}
			local groupLabels = {}
			for _, g in ipairs(groups) do
				groupIndex[g.Label] = g
				table.insert(groupLabels, g.Label)
			end
			local currentGroup = groupLabels[1] or ""

			local cardH = 115
			local gap   = 8

			local ctrlContainer = Instance.new("Frame")
			ctrlContainer.Name                = "FilteredCardGrid_Ctrl"
			ctrlContainer.BackgroundTransparency = 1
			ctrlContainer.Size                = UDim2.new(1, 0, 0, 34)
			ctrlContainer:SetAttribute("BackgroundTransparencyTarget", 1)  -- FIX: évite le bug de couleur au minimize/maximize
			ctrlContainer.Parent              = TabPage

			local dropBg = VMakeFrame(ctrlContainer,
				UDim2.new(1, 0, 0, 34),
				UDim2.new(0, 0, 0, 0),
				VC.BgLight, 0
			)
			VCorner(8, dropBg)
			VStroke(1, VC.BorderDim, dropBg)
			VMakeAccentBar(dropBg)

			VMakeLabel(dropBg, "Groupe",
				UDim2.new(0.45, 0, 1, 0),
				UDim2.new(0, 14, 0, 0),
				VC.TextMid, 11, Enum.Font.Gotham
			)

			local selLabel = VMakeLabel(dropBg, currentGroup,
				UDim2.new(0.42, -28, 1, 0),
				UDim2.new(0.45, 0, 0, 0),
				VC.TextBright, 12, Enum.Font.GothamBold,
				Enum.TextXAlignment.Right
			)

			local dropArrow = VMakeLabel(dropBg, "▾",
				UDim2.new(0, 16, 1, 0),
				UDim2.new(1, -20, 0, 0),
				VC.Accent, 12, Enum.Font.GothamBold,
				Enum.TextXAlignment.Center
			)

			local DROP_ITEM_H  = 28
			local DROP_MAX_H   = 252  -- max 9 items visibles (9*28)
			local dropFullH    = #groupLabels * DROP_ITEM_H + 6
			local dropH        = math.min(dropFullH, DROP_MAX_H)

			-- Conteneur extérieur (bordure + positionnement)
			local dropList = VMakeFrame(Rayfield.Main,
					UDim2.new(0, 0, 0, dropH),
					UDim2.new(0, 0, 0, 0),
					VC.BgMid, 0
			)
			dropList.Visible          = false
			dropList.ZIndex           = 60
			dropList.ClipsDescendants = false
			VCorner(8, dropList)
			VStroke(1, VC.Accent, dropList)



			-- ScrollingFrame intérieur : gère le scroll, les boutons vivent dedans
			local dropScroll = Instance.new("ScrollingFrame")
			dropScroll.Size                  = UDim2.new(1, 0, 0, dropH)
			dropScroll.Position              = UDim2.new(0, 0, 0, 0)
			dropScroll.BackgroundTransparency = 1
			dropScroll.BorderSizePixel       = 0
			dropScroll.ScrollBarThickness    = dropFullH > DROP_MAX_H and 4 or 0
			dropScroll.ScrollBarImageColor3  = VC.Accent
			dropScroll.CanvasSize            = UDim2.new(0, 0, 0, dropFullH)
			dropScroll.ScrollingDirection    = Enum.ScrollingDirection.Y
			dropScroll.ZIndex                = 61
			dropScroll.ClipsDescendants      = true
			dropScroll.Parent                = dropList

			local dropLayout = Instance.new("UIListLayout")
			dropLayout.SortOrder = Enum.SortOrder.LayoutOrder
			dropLayout.Parent    = dropScroll

			local dropOpen = false

			local function CloseDropdown()
				dropOpen         = false
				dropList.Visible = false
				dropArrow.Text   = "▾"
			end

			local function UpdateDropPos()
				local absPos  = dropBg.AbsolutePosition
				local absSize = dropBg.AbsoluteSize
				local sfPos   = Rayfield.Main.AbsolutePosition
				dropList.Size     = UDim2.new(0, absSize.X, 0, dropH)
				dropScroll.Size   = UDim2.new(1, 0, 0, dropH)
				dropList.Position = UDim2.new(0,
					absPos.X - sfPos.X,
					0,
					absPos.Y - sfPos.Y + absSize.Y + 2
				)
			end

			local gridContainer = Instance.new("Frame")
			gridContainer.Name                = "FilteredCardGrid_Grid"
			gridContainer.BackgroundTransparency = 1
			gridContainer.Size                = UDim2.new(1, 0, 0, 0)
			gridContainer:SetAttribute("BackgroundTransparencyTarget", 1)  -- FIX: évite le bug de couleur au minimize/maximize
			gridContainer.Parent              = TabPage

			local function RefreshScroll()
				task.defer(function()
					local layout = TabPage:FindFirstChildOfClass("UIListLayout")
					if layout then
						TabPage.CanvasSize = UDim2.new(0, 0, 0,
							layout.AbsoluteContentSize.Y + 20
						)
					end
				end)
			end

			local function BuildGrid(groupLabel)
				for _, child in ipairs(gridContainer:GetChildren()) do
					child:Destroy()
				end

				local grp = groupIndex[groupLabel]
				if not grp or #grp.Items == 0 then
					gridContainer.Size = UDim2.new(1, 0, 0, 0)
					RefreshScroll()
					return
				end

				local items   = grp.Items
				local rows    = math.ceil(#items / cols)
				local totalH2 = rows * (cardH + gap) + gap
				gridContainer.Size = UDim2.new(1, 0, 0, totalH2)

				local gridFrame = VMakeFrame(gridContainer, UDim2.new(1, 0, 1, 0), nil, VC.Black, 1)

				local gridLayout = Instance.new("UIGridLayout")
				gridLayout.CellSize      = UDim2.new(1/cols, -(gap * (cols + 1) / cols), 0, cardH)
				gridLayout.CellPadding   = UDim2.new(0, gap, 0, gap)
				gridLayout.SortOrder     = Enum.SortOrder.LayoutOrder
				gridLayout.FillDirection = Enum.FillDirection.Horizontal
				gridLayout.Parent        = gridFrame
				VPad(gap, gap, gap, gap, gridFrame)

				for i, item in ipairs(items) do
					local card = VMakeFrame(gridFrame, UDim2.new(0,1,0,1), nil, VC.BgMid, 0)
					card.LayoutOrder = i
					VCorner(10, card)
					local cardStroke = VStroke(1, VC.BorderDim, card)
					VGradient(VC.BgMid, VC.BgLight, card, 90)

					local img = Instance.new("ImageLabel")
					img.Size                   = UDim2.new(0.72, 0, 0, 68)
					img.Position               = UDim2.new(0.14, 0, 0, 7)
					img.BackgroundTransparency = 1
					img.Image                  = item.Icon or ""
					img.ScaleType              = Enum.ScaleType.Fit
					img.Parent                 = card

					local nameLabel = VMakeLabel(card,
						item.Name or "",
						UDim2.new(1, -6, 0, 18),
						UDim2.new(0, 3, 1, -22),
						VC.TextMid, 10, Enum.Font.GothamBold,
						Enum.TextXAlignment.Center
					)
					nameLabel.TextTruncate = Enum.TextTruncate.AtEnd

					local checkBg = VMakeFrame(card,
						UDim2.new(0, 22, 0, 22),
						UDim2.new(1, -26, 0, 4),
						VC.Accent, 1
					)
					VCorner(11, checkBg)
					local checkLabel = VMakeLabel(checkBg, "✓",
						UDim2.new(1,0,1,0), nil,
						VC.White, 12, Enum.Font.GothamBold,
						Enum.TextXAlignment.Center
					)
					checkLabel.TextYAlignment = Enum.TextYAlignment.Center

					local isSelected = globalSelected[item.Name] == true

					local function ApplyVisual(v)
						if v then
							VTween(cardStroke,  { Color = VC.Accent, Thickness = 2 },    0.15)
							VTween(card,        { BackgroundColor3 = VC.BgLighter },      0.15)
							VTween(checkBg,     { BackgroundTransparency = 0 },           0.15)
							VTween(nameLabel,   { TextColor3 = VC.TextBright },           0.15)
						else
							VTween(cardStroke,  { Color = VC.BorderDim, Thickness = 1 }, 0.15)
							VTween(card,        { BackgroundColor3 = VC.BgMid },          0.15)
							VTween(checkBg,     { BackgroundTransparency = 1 },           0.15)
							VTween(nameLabel,   { TextColor3 = VC.TextMid },              0.15)
						end
					end

					if isSelected then
						cardStroke.Color               = VC.Accent
						cardStroke.Thickness           = 2
						card.BackgroundColor3          = VC.BgLighter
						checkBg.BackgroundTransparency = 0
						nameLabel.TextColor3           = VC.TextBright
					end

					local clickZone = Instance.new("TextButton")
					clickZone.Size                 = UDim2.new(1,0,1,0)
					clickZone.BackgroundTransparency = 1
					clickZone.Text                 = ""
					clickZone.Parent               = card

					clickZone.MouseEnter:Connect(function()
						if not isSelected then
							VTween(card,       { BackgroundColor3 = VC.BgLight }, 0.12)
							VTween(cardStroke, { Color = VC.AccentGlow },         0.12)
						end
					end)
					clickZone.MouseLeave:Connect(function()
						if not isSelected then
							VTween(card,       { BackgroundColor3 = VC.BgMid },   0.12)
							VTween(cardStroke, { Color = VC.BorderDim },          0.12)
						end
					end)
					clickZone.MouseButton1Click:Connect(function()
						isSelected = not isSelected
						globalSelected[item.Name] = isSelected or nil
						ApplyVisual(isSelected)
						callback(globalSelected)
					end)
				end

				RefreshScroll()
			end

			for idx, label in ipairs(groupLabels) do
				local optBtn = Instance.new("TextButton")
				optBtn.Size                   = UDim2.new(1, 0, 0, 28)
				optBtn.BackgroundTransparency = 1
				optBtn.BorderSizePixel        = 0
				optBtn.Text                   = label
				optBtn.TextColor3             = VC.TextMid
				optBtn.TextSize               = 12
				optBtn.Font                   = Enum.Font.Gotham
				optBtn.ZIndex                 = 62
				optBtn.LayoutOrder            = idx
				optBtn.Parent                 = dropScroll

				optBtn.MouseEnter:Connect(function()
					VTween(optBtn, { TextColor3 = VC.TextBright }, 0.1)
					optBtn.BackgroundColor3       = VC.BgLight
					optBtn.BackgroundTransparency = 0
				end)
				optBtn.MouseLeave:Connect(function()
					VTween(optBtn, { TextColor3 = VC.TextMid }, 0.1)
					optBtn.BackgroundTransparency = 1
				end)
				optBtn.MouseButton1Click:Connect(function()
					currentGroup  = label
					selLabel.Text = label
					CloseDropdown()
					BuildGrid(label)
				end)
			end

			local dropClickZone = Instance.new("TextButton")
			dropClickZone.Size                 = UDim2.new(1, 0, 0, 34)
			dropClickZone.BackgroundTransparency = 1
			dropClickZone.Text                 = ""
			dropClickZone.Parent               = dropBg

			dropClickZone.MouseButton1Click:Connect(function()
				dropOpen = not dropOpen
				if dropOpen then
					UpdateDropPos()
					dropList.Visible = true
					dropArrow.Text   = "▴"
				else
					CloseDropdown()
				end
			end)

			UserInputService.InputBegan:Connect(function(input, processed)
				if input.UserInputType == Enum.UserInputType.MouseButton1 and dropOpen then
					if processed then return end  -- le clic a été capté par un bouton (option, flèche, etc.) — ne pas fermer
					local mp    = UserInputService:GetMouseLocation()
					local bPos  = dropBg.AbsolutePosition
					local bSize = dropBg.AbsoluteSize
					local dPos  = dropList.AbsolutePosition
					local dSize = dropList.AbsoluteSize
					local inBtn  = mp.X >= bPos.X and mp.X <= bPos.X + bSize.X and mp.Y >= bPos.Y and mp.Y <= bPos.Y + bSize.Y
					local inDrop = mp.X >= dPos.X and mp.X <= dPos.X + dSize.X and mp.Y >= dPos.Y and mp.Y <= dPos.Y + dSize.Y
					if not inBtn and not inDrop then CloseDropdown() end
				end
			end)


			BuildGrid(currentGroup)

			local fcgObj = {
				Type = "FilteredCardGrid",
				GetSelected = function() return globalSelected end,
				SetSelected = function(_, data)
					if type(data) ~= "table" then return end
					for k, v in pairs(data) do
						globalSelected[k] = v or nil
					end
					BuildGrid(currentGroup)
					callback(globalSelected)  -- fire le callback pour mettre à jour le script
				end,
				SelectAll = function(_, groupLabel)
					local grp = groupIndex[groupLabel or currentGroup]
					if not grp then return end
					for _, item in ipairs(grp.Items) do
						globalSelected[item.Name] = true
					end
					BuildGrid(currentGroup)
					callback(globalSelected)
				end,
				DeselectAll = function(_)
					globalSelected = {}
					BuildGrid(currentGroup)
					callback(globalSelected)
				end,
			}
			if cfg.Flag then
				RayfieldLibrary.Flags[cfg.Flag] = fcgObj
				_onComponentCreated()
			end
			return fcgObj
		end

		-- ── MULTI TOGGLE — plusieurs toggles indépendants sous un label ──────────
		function Tab:CreateMultiToggle(cfg)
			cfg = cfg or {}
			local options  = cfg.Options  or {}
			local callback = cfg.Callback or function() end
			local selected = {}
			local rowH     = 30

			local totalH = 24 + #options * (rowH + 5)

			local Container = Instance.new("Frame")
			Container.Name = "MultiToggle"
			Container.BackgroundTransparency = 1
			Container.Size = UDim2.new(1, 0, 0, totalH)
			Container:SetAttribute("BackgroundTransparencyTarget", 1)
			Container:SetAttribute("UIStrokeTransparencyTarget", 1)
			Container:SetAttribute("TitleTextTransparencyTarget", 1)
			Container.Parent = TabPage

			VMakeLabel(Container, cfg.Label or "Multi",
				UDim2.new(1, 0, 0, 22), nil,
				SelectedTheme.TextColor, 11, Enum.Font.GothamBold
			)

			local _rowRefs = {} -- {opt -> {pill, knob, setState}}

			for i, opt in ipairs(options) do
				local state = false
				local yPos  = 24 + (i - 1) * (rowH + 5)

				local row = VMakeFrame(Container,
					UDim2.new(1, 0, 0, rowH),
					UDim2.new(0, 0, 0, yPos),
					SelectedTheme.ElementBackground, 0
				)
				VCorner(8, row)
				VStroke(1, SelectedTheme.ElementStroke, row)
				VMakeAccentBar(row)

				VMakeLabel(row, opt,
					UDim2.new(1, -56, 1, 0),
					UDim2.new(0, 14, 0, 0),
					SelectedTheme.TextColor, 12, Enum.Font.Gotham
				)

				local pill = VMakeFrame(row,
					UDim2.new(0, 40, 0, 20),
					UDim2.new(1, -48, 0.5, -10),
					VC.BgDeep, 0
				)
				VCorner(10, pill)

				local knob = VMakeFrame(pill,
					UDim2.new(0, 14, 0, 14),
					UDim2.new(0, 2, 0.5, -7),
					VC.White, 0
				)
				VCorner(7, knob)

				local function applyVisual(v, instant)
					if v then
						if instant then pill.BackgroundColor3 = VC.Accent; knob.Position = UDim2.new(1, -16, 0.5, -7)
						else VTween(pill, { BackgroundColor3 = VC.Accent }, 0.18); VTween(knob, { Position = UDim2.new(1, -16, 0.5, -7) }, 0.18) end
					else
						if instant then pill.BackgroundColor3 = VC.BgDeep; knob.Position = UDim2.new(0, 2, 0.5, -7)
						else VTween(pill, { BackgroundColor3 = VC.BgDeep }, 0.18); VTween(knob, { Position = UDim2.new(0, 2, 0.5, -7) }, 0.18) end
					end
				end

				_rowRefs[opt] = { pill = pill, knob = knob, applyVisual = applyVisual,
					getState = function() return state end,
					setState = function(v) state = v end }

				local cz = Instance.new("TextButton")
				cz.Size                 = UDim2.new(1, 0, 1, 0)
				cz.BackgroundTransparency = 1
				cz.Text                 = ""
				cz.Parent               = row

				cz.MouseButton1Click:Connect(function()
					state = not state
					selected[opt] = state or nil
					applyVisual(state, false)
					callback(selected)
				end)
			end

			local mtObj = {
				Type = "MultiToggle",
				GetValue = function() return selected end,
				SetValue = function(_, data)
					if type(data) ~= "table" then return end
					for _, opt in ipairs(options) do
						local v = data[opt] == true
						selected[opt] = v or nil
						local ref = _rowRefs[opt]
						if ref then
							ref.setState(v)
							ref.applyVisual(v, true)
						end
					end
				end,
			}
			if cfg.Flag then
				RayfieldLibrary.Flags[cfg.Flag] = mtObj
				_onComponentCreated()
			end
			return mtObj
		end

		return Tab
	end

	Elements.Visible = true


	task.wait(1.1)
	TweenService:Create(Main, TweenInfo.new(0.7, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), {Size = UDim2.new(0, 390, 0, 90)}):Play()
	task.wait(0.3)
	TweenService:Create(LoadingFrame.Title, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(LoadingFrame.Subtitle, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	TweenService:Create(LoadingFrame.Version, TweenInfo.new(0.2, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
	task.wait(0.1)
	TweenService:Create(Main, TweenInfo.new(0.6, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out), {Size = useMobileSizing and UDim2.new(0, 500, 0, 275) or UDim2.new(0, 500, 0, 475)}):Play()
	TweenService:Create(Main.Shadow.Image, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {ImageTransparency = 0.6}):Play()

	Topbar.BackgroundTransparency = 1
	Topbar.Divider.Size = UDim2.new(0, 0, 0, 1)
	Topbar.Divider.BackgroundColor3 = SelectedTheme.ElementStroke
	Topbar.CornerRepair.BackgroundTransparency = 1
	Topbar.Title.TextTransparency = 1
	Topbar.Search.ImageTransparency = 1
	if Topbar:FindFirstChild('Settings') then
		Topbar.Settings.ImageTransparency = 1
	end
	Topbar.ChangeSize.ImageTransparency = 1
	Topbar.Hide.ImageTransparency = 1


	task.wait(0.5)
	Topbar.Visible = true
	TweenService:Create(Topbar, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	TweenService:Create(Topbar.CornerRepair, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0}):Play()
	task.wait(0.1)
	TweenService:Create(Topbar.Divider, TweenInfo.new(1, Enum.EasingStyle.Exponential), {Size = UDim2.new(1, 0, 0, 1)}):Play()
	TweenService:Create(Topbar.Title, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {TextTransparency = 0}):Play()
	task.wait(0.05)
	TweenService:Create(Topbar.Search, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
	task.wait(0.05)
	if Topbar:FindFirstChild('Settings') then
		TweenService:Create(Topbar.Settings, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
		task.wait(0.05)
	end
	TweenService:Create(Topbar.ChangeSize, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
	task.wait(0.05)
	TweenService:Create(Topbar.Hide, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
	task.wait(0.3)

	if dragBar then
		TweenService:Create(dragBarCosmetic, TweenInfo.new(0.6, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
	end

	-- ════════════════════════════════════════════════════════════════════════
	--  LAYOUT SIDE TABS — reconfigure TabList en sidebar verticale gauche
	--  et décale Elements à droite (activé si SideTabs = true)
	-- ════════════════════════════════════════════════════════════════════════
	if _sideTabMode then
		local sw = _sideTabWidth

		-- TabList → sidebar verticale gauche
		TabList.Size     = UDim2.new(0, sw, 1, -45)
		TabList.Position = UDim2.new(0, 0, 0, 45)
		TabList.BackgroundTransparency = 0
		TabList.BackgroundColor3 = SelectedTheme.Topbar

		local tll = TabList:FindFirstChildOfClass("UIListLayout")
		if tll then
			tll.FillDirection       = Enum.FillDirection.Vertical
			tll.HorizontalAlignment = Enum.HorizontalAlignment.Left
			tll.SortOrder           = Enum.SortOrder.LayoutOrder
			tll.Padding             = UDim.new(0, 4)
		end
		local tlp = TabList:FindFirstChildOfClass("UIPadding")
		if tlp then
			tlp.PaddingTop    = UDim.new(0, 6)
			tlp.PaddingBottom = UDim.new(0, 6)
			tlp.PaddingLeft   = UDim.new(0, 4)
			tlp.PaddingRight  = UDim.new(0, 4)
		end

		-- Elements → décalé à droite de la sidebar
		Elements.Size     = UDim2.new(1, -sw, 1, -45)
		Elements.Position = UDim2.new(0, sw, 0, 45)

		-- Diviseur vertical entre sidebar et contenu
		local sideDiv = Instance.new("Frame")
		sideDiv.Name             = "SideTabDivider"
		sideDiv.Size             = UDim2.new(0, 1, 1, -45)
		sideDiv.Position         = UDim2.new(0, sw, 0, 45)
		sideDiv.BackgroundColor3 = SelectedTheme.ElementStroke
		sideDiv.BorderSizePixel  = 0
		sideDiv.ZIndex           = 5
		sideDiv.Parent           = Main
	end

	function Window.ModifyTheme(NewTheme)
		local success = pcall(ChangeTheme, NewTheme)
		if not success then
			RayfieldLibrary:Notify({Title = 'Unable to Change Theme', Content = 'We are unable find a theme on file.', Image = 4400704299})
		else
			RayfieldLibrary:Notify({Title = 'Theme Changed', Content = 'Successfully changed theme to '..(typeof(NewTheme) == 'string' and NewTheme or 'Custom Theme')..'.', Image = 4483362748})
		end
	end

	-- ════════════════════════════════════════════════════════════════════════
	--  PAGE SETTINGS — créée comme tab caché (Ext=true), nom = 'Rayfield Settings'
	-- ════════════════════════════════════════════════════════════════════════
	local SettingsTab = Window:CreateTab('Rayfield Settings', 0, true)

	-- ════════════════════════════════════════════════════════════════════════
	--  SECTION CONFIGURATIONS — multi-slot par jeu
	-- ════════════════════════════════════════════════════════════════════════
	SettingsTab:CreateSection('Configurations')

	-- Déclarés avant le if : la section Share plus bas s'en sert aussi, et
	-- elle existe même quand la sauvegarde de config est désactivée.
	local slotDropdown, _refreshSlotDropdown

	if not CEnabled then
		SettingsTab:CreateLabel('Config saving is not enabled for this script.', nil, nil, true)
	else
		-- Dropdown des slots existants
		local configSlots = _listConfigs()
		local noSlots = #configSlots == 0
		if noSlots then configSlots = {"(none)"}end

		slotDropdown = SettingsTab:CreateDropdown({
			Name          = 'Active config',
			Options       = configSlots,
			CurrentOption = (CActiveSlot and {CActiveSlot}) or {configSlots[1]},
			Callback      = function() end,  -- on agit seulement via les boutons
		})

		-- Helper interne : rafraîchit le dropdown après création/suppression
		_refreshSlotDropdown = function()
			local slots = _listConfigs()
			if #slots == 0 then slots = {"(none)"} end
			slotDropdown:Refresh(slots)
			if CActiveSlot and table.find(slots, CActiveSlot) then
				slotDropdown:Set({CActiveSlot})
			elseif #slots > 0 and slots[1] ~= "(none)" then
				slotDropdown:Set({slots[1]})
			end
		end

		-- Charger le slot sélectionné
		SettingsTab:CreateButton({
			Name     = 'Load',
			Callback = function()
				local sel = slotDropdown.CurrentOption and slotDropdown.CurrentOption[1]
				if not sel or sel == "(none)" then
					RayfieldLibrary:Notify({Title = 'Config', Content = 'Select a config to load.', Duration = 3, Image = 4400704299})
					return
				end
				RayfieldLibrary:LoadConfiguration(sel)
			end,
		})

		-- Sauvegarder dans le slot actif
		SettingsTab:CreateButton({
			Name     = 'Save',
			Callback = function()
				local sel = slotDropdown.CurrentOption and slotDropdown.CurrentOption[1]
				if not sel or sel == "(none)" then
					RayfieldLibrary:Notify({Title = 'Config', Content = 'Select or create a config first.', Duration = 3, Image = 4400704299})
					return
				end
				SaveConfiguration(sel)
				RayfieldLibrary:Notify({Title = sel .. ' saved', Content = 'Full snapshot of current settings.', Duration = 3, Image = 4384403532})
			end,
		})

		-- Nouvelle config : nom via input + bouton
		local newSlotName = ""
		SettingsTab:CreateInput({
			Name            = 'New config name',
			PlaceholderText = 'e.g. tryhard, arena...',
			RemoveTextAfterFocusLost = false,
			Callback        = function(val)
				newSlotName = val:match("^%s*(.-)%s*$")  -- trim
			end,
		})

		SettingsTab:CreateButton({
			Name     = 'Create and save',
			Callback = function()
				if newSlotName == "" then
					RayfieldLibrary:Notify({Title = 'Config', Content = 'Enter a name for the new config.', Duration = 3, Image = 4400704299})
					return
				end
				-- Caractères interdits pour les noms de fichiers
				local safeName = newSlotName:gsub('[<>:"/\\|?*]', '_')
				SaveConfiguration(safeName)
				_refreshSlotDropdown()
				slotDropdown:Set({safeName})
				RayfieldLibrary:Notify({Title = safeName .. ' created', Content = 'Current values saved.', Duration = 3, Image = 4384403532})
				newSlotName = ""
			end,
		})

		-- Supprimer le slot sélectionné
		SettingsTab:CreateButton({
			Name     = 'Delete this config',
			Callback = function()
				local sel = slotDropdown.CurrentOption and slotDropdown.CurrentOption[1]
				if not sel or sel == "(none)" then return end
				local path = CPlaceFolder .. "/" .. sel .. ConfigurationExtension
				if callSafely(isfile, path) then
					callSafely(delfile, path)
				end
				-- Si c'était le slot actif, on désélectionne sans changer les valeurs
				if CActiveSlot == sel then
					CActiveSlot = nil
					_saveMeta()
				end
				_refreshSlotDropdown()
				RayfieldLibrary:Notify({Title = 'Config deleted', Content = sel .. ' was deleted. Your current settings are unchanged.', Duration = 4, Image = 4400704299})
			end,
		})

		SettingsTab:CreateDivider()

		-- Auto-load : dropdown pour choisir quel slot charger au lancement
		local autoLoadOptions = {"(disabled)"}
		for _, s in ipairs(_listConfigs()) do table.insert(autoLoadOptions, s) end

		local autoLoadDropdown = SettingsTab:CreateDropdown({
			Name          = 'Auto-load on launch',
			Options       = autoLoadOptions,
			CurrentOption = {CAutoLoadSlot or "(disabled)"},
			Callback      = function(sel)
				local chosen = sel[1] or sel
				CAutoLoadSlot = (chosen == "(disabled)") and nil or chosen
				_saveMeta()
			end,
		})

		-- Refresh du dropdown auto-load quand on crée/supprime une config
		local _origRefresh = _refreshSlotDropdown
		_refreshSlotDropdown = function()
			_origRefresh()
			local opts = {"(disabled)"}
			for _, s in ipairs(_listConfigs()) do table.insert(opts, s) end
			autoLoadDropdown:Refresh(opts)
			autoLoadDropdown:Set({CAutoLoadSlot or "(disabled)"})
		end
	end  -- CEnabled

	-- Partage/import d'une config via le worker voidhub-configs.
	SettingsTab:CreateSection('Share config')

	local shareBusy = false
	SettingsTab:CreateButton({
		Name     = 'Share my current config',
		Callback = function()
			if shareBusy then return end
			shareBusy = true
			task.spawn(function()
				local slot = slotDropdown and slotDropdown.CurrentOption and slotDropdown.CurrentOption[1]
				if slot == '(none)' then slot = nil end

				local res, err = _cfgShare.push(slot or 'Shared config')
				shareBusy = false

				if not res then
					RayfieldLibrary:Notify({Title = 'Share failed', Content = tostring(err), Duration = 6, Image = 4400704299, Force = true})
					return
				end

				local copied = pcall(setclipboard, res.url)
				RayfieldLibrary:Notify({
					Title    = 'Shared — code ' .. tostring(res.code),
					Content  = copied and 'Link copied to your clipboard, paste it wherever you want.'
					                   or  (tostring(res.url) .. ' — give this code to your friends.'),
					Duration = 10,
					Image    = 4384403532,
					Force    = true,
				})
			end)
		end,
	})

	local importCode = ''
	SettingsTab:CreateInput({
		Name            = 'Config code or link',
		PlaceholderText = 'e.g. AB3D7KP2',
		RemoveTextAfterFocusLost = false,
		Callback        = function(val) importCode = val end,
	})

	local importBusy = false
	SettingsTab:CreateButton({
		Name     = 'Import shared config',
		Callback = function()
			if importBusy then return end
			importBusy = true
			task.spawn(function()
				local res, err = _cfgShare.pull(importCode)
				importBusy = false

				if not res then
					RayfieldLibrary:Notify({Title = 'Import failed', Content = tostring(err), Duration = 6, Image = 4400704299, Force = true})
					return
				end

				local payload = HttpService:JSONEncode(res.config)

				-- On l'écrit d'abord comme slot local : la config importée
				-- survit à la session et se recharge comme n'importe quelle
				-- autre. Sans filesystem, on l'applique en mémoire seulement.
				if CEnabled and _hasFS and CPlaceFolder then
					local base = tostring(res.name or 'shared'):gsub('[<>:"/\\|?*]', '_')
					base = base:sub(1, 24):match('^%s*(.-)%s*$')
					if base == '' then base = 'shared' end

					local slotName = base .. ' ' .. res.code
					local path = CPlaceFolder .. '/' .. slotName .. ConfigurationExtension
					if callSafely(writefile, path, payload) ~= false then
						RayfieldLibrary:LoadConfiguration(slotName)
						if _refreshSlotDropdown then _refreshSlotDropdown() end
						return
					end
				end

				local ok, errors = LoadConfiguration(payload, false)
				if not ok then
					RayfieldLibrary:Notify({Title = 'Import failed', Content = (errors and errors[1]) or 'Unknown error.', Duration = 6, Image = 4400704299, Force = true})
				elseif #errors == 0 then
					RayfieldLibrary:Notify({Title = res.code, Content = '✅ Config imported.', Duration = 4, Image = 4384403532, Force = true})
				else
					RayfieldLibrary:Notify({Title = res.code, Content = '⚠️ Imported (' .. #errors .. ' flag(s) skipped).', Duration = 5, Image = 4400704299, Force = true})
				end
			end)
		end,
	})

	SettingsTab:CreateSection('Appearance')

	local themeNames = {}
	for name, _ in pairs(RayfieldLibrary.Theme) do
		table.insert(themeNames, name)
	end
	table.sort(themeNames)

	local currentThemeName = 'Default'
	for name, t in pairs(RayfieldLibrary.Theme) do
		if t == SelectedTheme then currentThemeName = name break end
	end

	SettingsTab:CreateDropdown({
		Name = 'Theme',
		Options = themeNames,
		CurrentOption = {currentThemeName},
		Flag = 'SettingsTheme',
		Callback = function(selected)
			local name = selected[1] or selected
			local ok, err = pcall(ChangeTheme, name)
			if not ok then
				RayfieldLibrary:Notify({Title = 'Theme not found', Content = 'Could not load theme "'..tostring(name)..'".'})
			end
		end,
	})

	SettingsTab:CreateSection('Shortcut')

	-- Rebind de la touche show/hide, EN DIRECT depuis les settings.
	-- CallOnChange = true : le Callback ne se declenche que quand on change
	-- la touche (pas quand on l'appuie -- c'est le handler hotkey global qui
	-- gere l'affichage). Le Flag persiste le choix dans la config du script.
	-- `newKey` arrive deja avec la bonne casse (RayVoid le derive de
	-- tostring(input.KeyCode)), donc on l'assigne tel quel -- le handler
	-- hotkey fait Enum.KeyCode[toggleKeybind] a chaque frame.
	SettingsTab:CreateKeybind({
		Name = 'Show/hide key',
		CurrentKeybind = toggleKeybind,
		HoldToInteract = false,
		CallOnChange = true,
		Flag = 'SettingsToggleKey',
		Callback = function(newKey)
			if type(newKey) == 'string' and newKey ~= '' then
				local ok = pcall(function() return Enum.KeyCode[newKey] end)
				if ok then
					toggleKeybind = newKey
				end
			end
		end,
	})

	SettingsTab:CreateSection('Information')

	SettingsTab:CreateParagraph({
		Title = 'Rayfield 2.0',
		Content = 'Interface by vwk4 - \nAll my scripts are free and keyless.',
	})

	-- ════════════════════════════════════════════════════════════════════════
	--  MAIN TAB — onglet d'accueil (Discord + liens). Remplace ShowCredit.
	--  Activé via Ui:MainCredit() AVANT CreateWindow.
	--  Construit ici APRÈS SettingsTab (qui est Ext/caché) et AVANT les onglets
	--  du script → devient le 1er onglet VISIBLE, sélectionné par défaut.
	-- ════════════════════════════════════════════════════════════════════════
	if _mainTabEnabled then
		local o = _mainTabOpts or {}
		local discordUrl = o.Discord or "https://discord.gg/ddu37DWPJn"
		local links = o.Links or {
			{ name = "RScripts",    url = "https://rscripts.net/@akkiwi" },
			{ name = "ScriptVerse", url = "https://scriptverse.net/u/akkiwi" },
			{ name = "ScriptBlox",  url = "https://scriptblox.com/u/Akkiwi" },
		}

		-- Icône de tab : valide le nom lucide, fallback sans icône si introuvable
		local iconArg = o.Icon
		if iconArg == nil then iconArg = "home" end
		if type(iconArg) == "string" then
			local okIcon, iconRes = pcall(getIcon, iconArg)
			if not okIcon or not iconRes then iconArg = 0 end
		end

		local MainTab = Window:CreateTab(o.TabName or "Main", iconArg)

		-- Warning executor non supporté (Xeno / Solara) — label rouge persistant
		local _execName = "Unknown"
		pcall(function() _execName = identifyexecutor() or "Unknown" end)
		local _low = string.lower(_execName)
		if string.find(_low, "xeno", 1, true) or string.find(_low, "solara", 1, true) then
			MainTab:CreateLabel(
				"[!] " .. _execName .. " is NOT supported and may cause errors. Join the Discord for a working executor.",
				nil,
				Color3.fromRGB(230, 55, 75),
				true
			)
		end

		MainTab:CreateSection("")

		MainTab:CreateRichParagraph({
			Color   = Color3.fromRGB(85, 220, 120),
			Title   = '<font color="#55DC78"> 100% FREE &amp; KEYLESS — ALWAYS</font>',
			Content = '<font color="#FF6B6B"><b>Asked for a key? You got SCAMMED.</b></font>\n'
				.. '<font color="#D8D5F0">Every script I make is free and keyless. No paywalls, no offerwalls, no keys.</font>\n',	
		})

		MainTab:CreateSection("💬 Community")

		MainTab:CreateRichParagraph({
			Color   = Color3.fromRGB(120, 140, 255),
			Title   = '<font color="#8AA0FF">Join the Discord</font>',
			Content = '<font color="#D8D5F0">New scripts, updates, sneak peeks and script requests all happen here.</font>\n'
				.. '<font color="#FFC466">🎫 Found a bug or want a script updated? Open a ticket on the Discord.</font>\n'
				.. '<font color="#8AA0FF">👇 ' .. (discordUrl:gsub("https://", "")) .. '</font>',
		})

		MainTab:CreateButton({
			Name = "📋 Copy Discord invite  (" .. (discordUrl:gsub("https://", "")) .. ")",
			Callback = function()
				pcall(setclipboard, discordUrl)
				RayfieldLibrary:Notify({
					Title = "Discord copied ✅",
					Content = "Invite copied to clipboard — paste it in your browser!",
					Duration = 4,
					Image = 4483362748,
				})
			end,
		})

		MainTab:CreateSection("❤️ Support Me")

		local paypalUrl = o.PayPal or "https://paypal.me/Akkiwi"
		local solanaAddr = o.Solana or "3kj4auRyaqcW2PQ8MYFBcEEueV6PXUhdntYNBEHqYpzZ"

		MainTab:CreateRichParagraph({
			Color   = Color3.fromRGB(255, 120, 160),
			Title   = '<font color="#FF78A0">Want to support me?</font>',
			Content = '<font color="#D8D5F0">My scripts will always stay free. If you enjoy them and want to support my work, you can make a donation — every bit helps, thank you! 💖</font>',
		})

		for _, don in ipairs({
			{ name = "PayPal", label = "📋 Copy PayPal link  (" .. (paypalUrl:gsub("https://", "")) .. ")", value = paypalUrl },
			{ name = "Solana address", label = "📋 Copy Solana (SOL) address", value = solanaAddr },
		}) do
			MainTab:CreateButton({
				Name = don.label,
				Callback = function()
					pcall(setclipboard, don.value)
					RayfieldLibrary:Notify({
						Title = don.name .. " copied ✅",
						Content = "Thank you for your support! 💖",
						Duration = 4,
						Image = 4483362748,
					})
				end,
			})
		end

		MainTab:CreateSection("🔗 My Script Pages")

		MainTab:CreateRichParagraph({
			Content = '<font color="#A5A0C0">Find all my scripts on these sites. Tap a button below to copy the link.</font>',
		})

		for _, lnk in ipairs(links) do
			MainTab:CreateButton({
				Name = "📋 Copy " .. lnk.name .. " link",
				Callback = function()
					pcall(setclipboard, lnk.url)
					RayfieldLibrary:Notify({
						Title = lnk.name .. " copied ✅",
						Content = "Link copied to clipboard.",
						Duration = 3,
						Image = 4483362748,
					})
				end,
			})
		end
	end

	return Window
end

local function setVisibility(visibility: boolean, notify: boolean?)
	if Debounce then return end
	if visibility then
		Hidden = false
		task.spawn(Unhide)
	else
		Hidden = true
		task.spawn(Hide, notify)
	end
end

function RayfieldLibrary:SetVisibility(visibility: boolean)
	setVisibility(visibility, false)
end

function RayfieldLibrary:IsVisible(): boolean
	return not Hidden
end

-- Rebind (au runtime) la touche qui affiche/cache l'UI. Accepte une string
-- ("K", "RightShift"...) ou un Enum.KeyCode. Le handler hotkey lit
-- `toggleKeybind` en direct a chaque InputBegan, donc le changement est
-- immediat, sans reconnexion. Equivalent runtime de Settings.ToggleUIKeybind
-- passe a CreateWindow.
function RayfieldLibrary:SetToggleKeybind(key)
	local name
	if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
		name = key.Name
	elseif type(key) == "string" and key ~= "" then
		-- D'abord tel quel (respecte la casse : "RightShift", "LeftControl"),
		-- sinon en MAJUSCULES (pour "k" -> "K"). Enum.KeyCode["RIGHTSHIFT"]
		-- n'existe pas, donc string.upper ne marche QUE pour les touches a
		-- un seul caractere -- d'ou l'essai as-is en premier.
		local ok, kc = pcall(function() return Enum.KeyCode[key] end)
		if ok and typeof(kc) == "EnumItem" then
			name = kc.Name
		else
			local ok2, kc2 = pcall(function() return Enum.KeyCode[string.upper(key)] end)
			if ok2 and typeof(kc2) == "EnumItem" then
				name = kc2.Name
			end
		end
	end
	if not name then
		warn("[Rayfield] SetToggleKeybind: KeyCode invalide (" .. tostring(key) .. "), ignore")
		return false
	end
	toggleKeybind = name
	return true
end

local hideHotkeyConnection -- Has to be initialized here since the connection is made later in the script
function RayfieldLibrary:Destroy()
	rayfieldDestroyed = true
	if hideHotkeyConnection then
		hideHotkeyConnection:Disconnect()
	end
	for _, connection in keybindConnections do
		connection:Disconnect()
	end
	pcall(function() _reopenSg:Destroy() end)
	Rayfield:Destroy()
end

Topbar.ChangeSize.MouseButton1Click:Connect(function()
	if Debounce then return end
	if Minimised then
		Minimised = false
		Maximise()
	else
		Minimised = true
		Minimise()
	end
end)

Main.Search.Input:GetPropertyChangedSignal('Text'):Connect(function()
	if #Main.Search.Input.Text > 0 then
		if not Elements.UIPageLayout.CurrentPage:FindFirstChild('SearchTitle-fsefsefesfsefesfesfThanks') then 
			local searchTitle = Elements.Template.SectionTitle:Clone()
			searchTitle.Parent = Elements.UIPageLayout.CurrentPage
			searchTitle.Name = 'SearchTitle-fsefsefesfsefesfesfThanks'
			searchTitle.LayoutOrder = -100
			searchTitle.Title.Text = "Results from '"..Elements.UIPageLayout.CurrentPage.Name.."'"
			searchTitle.Visible = true
		end
	else
		local searchTitle = Elements.UIPageLayout.CurrentPage:FindFirstChild('SearchTitle-fsefsefesfsefesfesfThanks')

		if searchTitle then
			searchTitle:Destroy()
		end
	end

	for _, element in ipairs(Elements.UIPageLayout.CurrentPage:GetChildren()) do
		if element.ClassName ~= 'UIListLayout' and element.Name ~= 'Placeholder' and element.Name ~= 'SearchTitle-fsefsefesfsefesfesfThanks' then
			if element.Name == 'SectionTitle' then
				if #Main.Search.Input.Text == 0 then
					element.Visible = true
				else
					element.Visible = false
				end
			else
				if string.lower(element.Name):find(string.lower(Main.Search.Input.Text), 1, true) then
					element.Visible = true
				else
					element.Visible = false
				end
			end
		end
	end
end)

Main.Search.Input.FocusLost:Connect(function(enterPressed)
	if #Main.Search.Input.Text == 0 and searchOpen then
		task.wait(0.12)
		closeSearch()
	end
end)

Topbar.Search.MouseButton1Click:Connect(function()
	task.spawn(function()
		if searchOpen then
			closeSearch()
		else
			openSearch()
		end
	end)
end)

if Topbar:FindFirstChild('Settings') then
	local _settingsOpen = false
	local _lastPage = nil

	Topbar.Settings.MouseButton1Click:Connect(function()
		task.spawn(function()
			local settingsPage = Elements:FindFirstChild('Rayfield Settings')
			if not settingsPage then return end

			if _settingsOpen then
				-- Retour au tab précédent
				_settingsOpen = false
				TweenService:Create(Topbar.Settings, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageColor3 = SelectedTheme.TextColor}):Play()
				if _lastPage and _lastPage.Parent then
					Elements.UIPageLayout.Animated = false
					Elements.UIPageLayout:JumpTo(_lastPage)
					Elements.UIPageLayout.Animated = true
				end
			else
				-- Ouverture settings
				_settingsOpen = true
				_lastPage = Elements.UIPageLayout.CurrentPage
				TweenService:Create(Topbar.Settings, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {ImageColor3 = SelectedTheme.SliderProgress}):Play()

				for _, OtherTabButton in ipairs(TabList:GetChildren()) do
					if OtherTabButton.Name ~= "Template" and OtherTabButton.ClassName == "Frame" and OtherTabButton.Name ~= "Placeholder" then
						TweenService:Create(OtherTabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundColor3 = SelectedTheme.TabBackground}):Play()
						TweenService:Create(OtherTabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextColor3 = SelectedTheme.TabTextColor}):Play()
						TweenService:Create(OtherTabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageColor3 = SelectedTheme.TabTextColor}):Play()
						TweenService:Create(OtherTabButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {BackgroundTransparency = 0.7}):Play()
						TweenService:Create(OtherTabButton.Title, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {TextTransparency = 0.2}):Play()
						TweenService:Create(OtherTabButton.Image, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.2}):Play()
						TweenService:Create(OtherTabButton.UIStroke, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {Transparency = 0.5}):Play()
					end
				end

				Elements.UIPageLayout:JumpTo(settingsPage)
			end
		end)
	end)

end


Topbar.Hide.MouseButton1Click:Connect(function()
	setVisibility(Hidden, not useMobileSizing)
end)

-- Connect du bouton flottant (ici car Unhide est déclarée au-dessus)
_reopenBtn.MouseButton1Click:Connect(function()
	if Hidden and not Debounce then
		Hidden = false
		task.spawn(Unhide)
	end
end)

hideHotkeyConnection = UserInputService.InputBegan:Connect(function(input, processed)
	if (input.KeyCode == Enum.KeyCode[toggleKeybind]) and not processed then
		if Debounce then return end
		if Hidden then
			Hidden = false
			task.spawn(Unhide)
		else
			Hidden = true
			task.spawn(Hide)
		end
	end
end)

if MPrompt then
	MPrompt.Interact.MouseButton1Click:Connect(function()
		if Debounce then return end
		if Hidden then
			Hidden = false
			Unhide()
		end
	end)
end

for _, TopbarButton in ipairs(Topbar:GetChildren()) do
	if TopbarButton.ClassName == "ImageButton" and TopbarButton.Name ~= 'Icon' then
		TopbarButton.MouseEnter:Connect(function()
			TweenService:Create(TopbarButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0}):Play()
		end)

		TopbarButton.MouseLeave:Connect(function()
			TweenService:Create(TopbarButton, TweenInfo.new(0.7, Enum.EasingStyle.Exponential), {ImageTransparency = 0.8}):Play()
		end)
	end
end


-- Loads the given slot (or CActiveSlot) and shows a single clean notification.
-- slotName optional, falls back to CActiveSlot.
-- retry optional: when true (auto-load), flags whose callback throws because the
-- game isn't ready yet get retried for a few seconds instead of being reported
-- as errors.
function RayfieldLibrary:LoadConfiguration(slotName, retry)
	slotName = slotName or CActiveSlot
	if not CEnabled then return end
	if not slotName or slotName == "" then return end
	if not CPlaceFolder then return end
	if not _hasFS then return end

	local path = CPlaceFolder .. "/" .. slotName .. ConfigurationExtension
	if not callSafely(isfile, path) then
		RayfieldLibrary:Notify({Title = slotName, Content = "❌ File not found.", Duration = 4, Image = 4400704299})
		return
	end

	local raw = callSafely(readfile, path)
	if not raw then
		RayfieldLibrary:Notify({Title = slotName, Content = "❌ Could not read file.", Duration = 4, Image = 4400704299})
		return
	end

	local ok, errors = LoadConfiguration(raw, retry)
	if not ok then
		RayfieldLibrary:Notify({Title = slotName, Content = "❌ " .. (errors[1] or "Unknown error."), Duration = 6, Image = 4400704299, Force = true})
		return
	end

	CActiveSlot = slotName
	_saveMeta()

	if #errors == 0 then
		RayfieldLibrary:Notify({Title = slotName, Content = "✅ Config loaded.", Duration = 3, Image = 4384403532, Force = true})
	else
		RayfieldLibrary:Notify({Title = slotName, Content = "⚠️ Loaded (" .. #errors .. " flag(s) skipped).", Duration = 5, Image = 4400704299, Force = true})
	end

	globalLoaded = true
end



if useStudio then
	-- run w/ studio
	-- Feel free to place your own script here to see how it'd work in Roblox Studio before running it on your execution software.


	--local Window = RayfieldLibrary:CreateWindow({
	--	Name = "Rayfield Example Window",
	--	LoadingTitle = "Rayfield Interface Suite",
	--	Theme = 'Default',
	--	Icon = 0,
	--	LoadingSubtitle = "by Sirius",
	--	ConfigurationSaving = {
	--		Enabled = true,
	--		FolderName = nil, -- Create a custom folder for your hub/game
	--		FileName = "Big Hub52"
	--	},
	--	Discord = {
	--		Enabled = false,
	--		Invite = "noinvitelink", -- The Discord invite code, do not include discord.gg/. E.g. discord.gg/ABCD would be ABCD
	--		RememberJoins = true -- Set this to false to make them join the discord every time they load it up
	--	},
	--	KeySystem = false, -- Set this to true to use our key system
	--	KeySettings = {
	--		Title = "Untitled",
	--		Subtitle = "Key System",
	--		Note = "No method of obtaining the key is provided",
	--		FileName = "Key", -- It is recommended to use something unique as other scripts using Rayfield may overwrite your key file
	--		SaveKey = true, -- The user's key will be saved, but if you change the key, they will be unable to use your script
	--		GrabKeyFromSite = false, -- If this is true, set Key below to the RAW site you would like Rayfield to get the key from
	--		Key = {"Hello"} -- List of keys that will be accepted by the system, can be RAW file links (pastebin, github etc) or simple strings ("hello","key22")
	--	}
	--})

	--local Tab = Window:CreateTab("Tab Example", 'key-round') -- Title, Image
	--local Tab2 = Window:CreateTab("Tab Example 2", 4483362458) -- Title, Image

	--local Section = Tab2:CreateSection("Section")


	--local ColorPicker = Tab2:CreateColorPicker({
	--	Name = "Color Picker",
	--	Color = Color3.fromRGB(255,255,255),
	--	Flag = "ColorPicfsefker1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place every time the color picker is moved/changed
	--		-- The variable (Value) is a Color3fromRGB value based on which color is selected
	--	end
	--})

	--local Slider = Tab2:CreateSlider({
	--	Name = "Slider Example",
	--	Range = {0, 100},
	--	Increment = 10,
	--	Suffix = "Bananas",
	--	CurrentValue = 40,
	--	Flag = "Slidefefsr1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place when the slider changes
	--		-- The variable (Value) is a number which correlates to the value the slider is currently at
	--	end,
	--})

	--local Input = Tab2:CreateInput({
	--	Name = "Input Example",
	--	CurrentValue = '',
	--	PlaceholderText = "Input Placeholder",
	--	Flag = 'dawdawd',
	--	RemoveTextAfterFocusLost = false,
	--	Callback = function(Text)
	--		-- The function that takes place when the input is changed
	--		-- The variable (Text) is a string for the value in the text box
	--	end,
	--})


	----RayfieldLibrary:Notify({Title = "Rayfield Interface", Content = "Welcome to Rayfield. These - are the brand new notification design for Rayfield, with custom sizing and Rayfield calculated wait times.", Image = 4483362458})

	--local Section = Tab:CreateSection("Section Example")

	--local Button = Tab:CreateButton({
	--	Name = "Change Theme",
	--	Callback = function()
	--		-- The function that takes place when the button is pressed
	--		Window.ModifyTheme('DarkBlue')
	--	end,
	--})

	--local Toggle = Tab:CreateToggle({
	--	Name = "Toggle Example",
	--	CurrentValue = false,
	--	Flag = "Toggle1adwawd", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place when the toggle is pressed
	--		-- The variable (Value) is a boolean on whether the toggle is true or false
	--	end,
	--})

	--local ColorPicker = Tab:CreateColorPicker({
	--	Name = "Color Picker",
	--	Color = Color3.fromRGB(255,255,255),
	--	Flag = "ColorPicker1awd", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place every time the color picker is moved/changed
	--		-- The variable (Value) is a Color3fromRGB value based on which color is selected
	--	end
	--})

	--local Slider = Tab:CreateSlider({
	--	Name = "Slider Example",
	--	Range = {0, 100},
	--	Increment = 10,
	--	Suffix = "Bananas",
	--	CurrentValue = 40,
	--	Flag = "Slider1dawd", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Value)
	--		-- The function that takes place when the slider changes
	--		-- The variable (Value) is a number which correlates to the value the slider is currently at
	--	end,
	--})

	--local Input = Tab:CreateInput({
	--	Name = "Input Example",
	--	CurrentValue = "Helo",
	--	PlaceholderText = "Adaptive Input",
	--	RemoveTextAfterFocusLost = false,
	--	Flag = 'Input1',
	--	Callback = function(Text)
	--		-- The function that takes place when the input is changed
	--		-- The variable (Text) is a string for the value in the text box
	--	end,
	--})

	--local thoptions = {}
	--for themename, theme in pairs(RayfieldLibrary.Theme) do
	--	table.insert(thoptions, themename)
	--end

	--local Dropdown = Tab:CreateDropdown({
	--	Name = "Theme",
	--	Options = thoptions,
	--	CurrentOption = {"Default"},
	--	MultipleOptions = false,
	--	Flag = "Dropdown1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Options)
	--		--Window.ModifyTheme(Options[1])
	--		-- The function that takes place when the selected option is changed
	--		-- The variable (Options) is a table of strings for the current selected options
	--	end,
	--})


	--Window.ModifyTheme({
	--	TextColor = Color3.fromRGB(50, 55, 60),
	--	Background = Color3.fromRGB(240, 245, 250),
	--	Topbar = Color3.fromRGB(215, 225, 235),
	--	Shadow = Color3.fromRGB(200, 210, 220),

	--	NotificationBackground = Color3.fromRGB(210, 220, 230),
	--	NotificationActionsBackground = Color3.fromRGB(225, 230, 240),

	--	TabBackground = Color3.fromRGB(200, 210, 220),
	--	TabStroke = Color3.fromRGB(180, 190, 200),
	--	TabBackgroundSelected = Color3.fromRGB(175, 185, 200),
	--	TabTextColor = Color3.fromRGB(50, 55, 60),
	--	SelectedTabTextColor = Color3.fromRGB(30, 35, 40),

	--	ElementBackground = Color3.fromRGB(210, 220, 230),
	--	ElementBackgroundHover = Color3.fromRGB(220, 230, 240),
	--	SecondaryElementBackground = Color3.fromRGB(200, 210, 220),
	--	ElementStroke = Color3.fromRGB(190, 200, 210),
	--	SecondaryElementStroke = Color3.fromRGB(180, 190, 200),

	--	SliderBackground = Color3.fromRGB(200, 220, 235),  -- Lighter shade
	--	SliderProgress = Color3.fromRGB(70, 130, 180),
	--	SliderStroke = Color3.fromRGB(150, 180, 220),

	--	ToggleBackground = Color3.fromRGB(210, 220, 230),
	--	ToggleEnabled = Color3.fromRGB(70, 160, 210),
	--	ToggleDisabled = Color3.fromRGB(180, 180, 180),
	--	ToggleEnabledStroke = Color3.fromRGB(60, 150, 200),
	--	ToggleDisabledStroke = Color3.fromRGB(140, 140, 140),
	--	ToggleEnabledOuterStroke = Color3.fromRGB(100, 120, 140),
	--	ToggleDisabledOuterStroke = Color3.fromRGB(120, 120, 130),

	--	DropdownSelected = Color3.fromRGB(220, 230, 240),
	--	DropdownUnselected = Color3.fromRGB(200, 210, 220),

	--	InputBackground = Color3.fromRGB(220, 230, 240),
	--	InputStroke = Color3.fromRGB(180, 190, 200),
	--	PlaceholderColor = Color3.fromRGB(150, 150, 150)
	--})

	--local Keybind = Tab:CreateKeybind({
	--	Name = "Keybind Example",
	--	CurrentKeybind = "Q",
	--	HoldToInteract = false,
	--	Flag = "Keybind1", -- A flag is the identifier for the configuration file, make sure every element has a different flag if you're using configuration saving to ensure no overlaps
	--	Callback = function(Keybind)
	--		-- The function that takes place when the keybind is pressed
	--		-- The variable (Keybind) is a boolean for whether the keybind is being held or not (HoldToInteract needs to be true)
	--	end,
	--})

	--local Label = Tab:CreateLabel("Label Example")

	--local Label2 = Tab:CreateLabel("Warning", 4483362458, Color3.fromRGB(255, 159, 49),  true)

	--local Paragraph = Tab:CreateParagraph({Title = "Paragraph Example", Content = "Paragraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph ExampleParagraph Example"})
end

if CEnabled and Main:FindFirstChild('Notice') then
	Main.Notice.BackgroundTransparency = 1
	Main.Notice.Title.TextTransparency = 1
	Main.Notice.Size = UDim2.new(0, 0, 0, 0)
	Main.Notice.Position = UDim2.new(0.5, 0, 0, -100)
	Main.Notice.Visible = true


	TweenService:Create(Main.Notice, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), {Size = UDim2.new(0, 280, 0, 35), Position = UDim2.new(0.5, 0, 0, -50), BackgroundTransparency = 0.5}):Play()
	TweenService:Create(Main.Notice.Title, TweenInfo.new(0.5, Enum.EasingStyle.Exponential), {TextTransparency = 0.1}):Play()
end


task.delay(4, function()
	-- Masquage de la notice si visible
	if Main:FindFirstChild('Notice') and Main.Notice.Visible then
		TweenService:Create(Main.Notice, TweenInfo.new(0.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.InOut), {Size = UDim2.new(0, 100, 0, 25), Position = UDim2.new(0.5, 0, 0, -100), BackgroundTransparency = 1}):Play()
		TweenService:Create(Main.Notice.Title, TweenInfo.new(0.3, Enum.EasingStyle.Exponential), {TextTransparency = 1}):Play()
		task.wait(0.5)
		Main.Notice.Visible = false
	end
end)

-- ── UI READY WATCHER — thème et auto-load déclenchés quand l'UI est construite
-- Détecte le silence de UI_READY_DELAY secondes sans nouveau composant créé.
task.spawn(function()
	-- Attendre qu'au moins un composant ait été enregistré (UI a commencé à se construire)
	while _lastComponentTime == 0 do
		task.wait(0.1)
		if rayfieldDestroyed then return end
	end
	-- Puis attendre le silence
	while true do
		task.wait(0.1)
		if rayfieldDestroyed then return end
		if tick() - _lastComponentTime >= UI_READY_DELAY then
			if _uiReadyFired then break end
			_uiReadyFired = true

			-- 1. Apply saved theme (needs the UI to be built)
			if _pendingTheme then
				pcall(ChangeTheme, _pendingTheme)
				_pendingTheme = nil
			end

			-- 2. Auto-load if a slot is configured.
			-- retry=true: callbacks that fail because the game isn't ready yet
			-- (character/remotes/workspace) get retried instead of erroring.
			-- Spawned so the retry waits don't block this watcher loop.
			if CEnabled and CAutoLoadSlot then
				task.spawn(function()
					RayfieldLibrary:LoadConfiguration(CAutoLoadSlot, true)
				end)
			end

			break
		end
	end
end)

-- ════════════════════════════════════════════════════════════════════════════
--  FLOATING BUTTON — bouton flottant draggable indépendant de la fenêtre
-- ════════════════════════════════════════════════════════════════════════════
function RayfieldLibrary:CreateFloatingButton(cfg)
	cfg = cfg or {}
	local icon     = cfg.Icon     or ""
	local text     = cfg.Text     or ""
	local pos      = cfg.Position or UDim2.new(0, 20, 0.5, 0)
	local btnSize  = cfg.Size     or UDim2.new(0, 52, 0, 52)
	local callback = cfg.Callback or function() end
	local hasIcon  = icon ~= ""

	local sg = Instance.new("ScreenGui")
	sg.Name           = "Rayfield_FloatBtn_" .. (hasIcon and "img" or text)
	sg.ResetOnSpawn   = false
	sg.DisplayOrder   = 1000
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local ok = pcall(function() sg.Parent = CoreGui end)
	if not ok then sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

	local btn = Instance.new("TextButton")
	btn.Size             = btnSize
	btn.Position         = pos
	btn.BackgroundColor3 = VC.BgMid
	btn.BorderSizePixel  = 0
	btn.Text             = ""
	btn.ZIndex           = 10
	btn.Parent           = sg
	VCorner(14, btn)
	VStroke(4, VC.Black, btn)
	local innerStroke = VStroke(1.5, VC.Accent, btn)

	if hasIcon then
		local img = Instance.new("ImageLabel")
		img.Size                   = UDim2.new(0.72, 0, 0.72, 0)
		img.Position               = UDim2.new(0.14, 0, 0.14, 0)
		img.BackgroundTransparency = 1
		img.Image                  = icon
		img.ScaleType              = Enum.ScaleType.Fit
		img.ZIndex                 = 11
		img.Parent                 = btn
	else
		local lbl = Instance.new("TextLabel")
		lbl.Size                   = UDim2.new(1, -8, 1, -8)
		lbl.Position               = UDim2.new(0, 4, 0, 4)
		lbl.BackgroundTransparency = 1
		lbl.Text                   = text
		lbl.TextColor3             = VC.TextBright
		lbl.TextSize               = 12
		lbl.Font                   = Enum.Font.GothamBold
		lbl.TextWrapped            = true
		lbl.ZIndex                 = 11
		lbl.Parent                 = btn
	end

	btn.MouseEnter:Connect(function()
		VTween(btn, { BackgroundColor3 = VC.BgLight }, 0.12)
		VTween(innerStroke, { Color = VC.AccentGlow }, 0.12)
	end)
	btn.MouseLeave:Connect(function()
		VTween(btn, { BackgroundColor3 = VC.BgMid }, 0.12)
		VTween(innerStroke, { Color = VC.Accent }, 0.12)
	end)
	btn.MouseButton1Down:Connect(function()
		VTween(btn, { BackgroundColor3 = VC.AccentSoft }, 0.08)
	end)
	btn.MouseButton1Up:Connect(function()
		VTween(btn, { BackgroundColor3 = VC.BgMid }, 0.12)
	end)

	local dragging  = false
	local dragStart = nil
	local startPos  = nil
	local moved     = false

	btn.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging  = true
			moved     = false
			dragStart = input.Position
			startPos  = btn.Position
		end
	end)
	btn.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
			if not moved then callback() end
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			if math.abs(delta.X) > 4 or math.abs(delta.Y) > 4 then
				moved = true
			end
			if moved then
				btn.Position = UDim2.new(
					startPos.X.Scale, startPos.X.Offset + delta.X,
					startPos.Y.Scale, startPos.Y.Offset + delta.Y
				)
			end
		end
	end)

	return {
		SetIcon = function(_, id)
			local img = btn:FindFirstChildOfClass("ImageLabel")
			if img then img.Image = id end
		end,
		SetText = function(_, v)
			local lbl = btn:FindFirstChildOfClass("TextLabel")
			if lbl then lbl.Text = v end
		end,
		SetVisible = function(_, v) btn.Visible = v end,
		Destroy    = function(_)    sg:Destroy() end,
	}
end

-- ════════════════════════════════════════════════════════════════════════════
--  OVERLAY — widget flottant draggable pour afficher des infos en temps réel
-- ════════════════════════════════════════════════════════════════════════════
function RayfieldLibrary:CreateOverlay(cfg)
	cfg = cfg or {}
	local items    = cfg.Items    or {}
	local pos      = cfg.Position or UDim2.new(0, 20, 0, 120)
	local minWidth = cfg.Width    or 160

	local totalH = 12
	for _, item in ipairs(items) do
		if item.Type == "text"          then totalH = totalH + 22
		elseif item.Type == "image"     then totalH = totalH + 50
		elseif item.Type == "separator" then totalH = totalH + 10
		end
	end

	local sg = Instance.new("ScreenGui")
	sg.Name           = "Rayfield_Overlay"
	sg.ResetOnSpawn   = false
	sg.DisplayOrder   = 998
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	local ok = pcall(function() sg.Parent = CoreGui end)
	if not ok then sg.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

	local container = VMakeFrame(sg,
		UDim2.new(0, minWidth, 0, totalH),
		pos,
		VC.BgMid, 0
	)
	VCorner(10, container)
	VStroke(4, VC.Black, container)
	VStroke(1.5, VC.Accent, container)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding   = UDim.new(0, 4)
	layout.Parent    = container
	VPad(6, 6, 8, 8, container)

	local dragging  = false
	local dragStart = nil
	local startPos  = nil
	container.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging  = true
			dragStart = input.Position
			startPos  = container.Position
		end
	end)
	container.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = false
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local delta = input.Position - dragStart
			container.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)

	local elements = {}
	local order    = 0

	for _, item in ipairs(items) do
		order = order + 1
		if item.Type == "text" then
			local lbl = VMakeLabel(container,
				item.Text or "",
				UDim2.new(1, 0, 0, 20), nil,
				item.Color or VC.TextBright,
				item.TextSize or 12,
				item.Bold and Enum.Font.GothamBold or Enum.Font.Gotham
			)
			lbl.LayoutOrder    = order
			lbl.TextXAlignment = item.Align or Enum.TextXAlignment.Left
			if item.Id then elements[item.Id] = lbl end

		elseif item.Type == "image" then
			local img = Instance.new("ImageLabel")
			img.Size                   = UDim2.new(1, 0, 0, item.Height or 44)
			img.BackgroundTransparency = 1
			img.Image                  = item.Icon or ""
			img.ScaleType              = Enum.ScaleType.Fit
			img.LayoutOrder            = order
			img.Parent                 = container
			if item.Id then elements[item.Id] = img end

		elseif item.Type == "imagebutton" then
			local btnH   = (item.Height or 44) + (item.Label and 20 or 0)
			local ibWrap = VMakeFrame(container, UDim2.new(1,0,0,btnH), nil, VC.Black, 1)
			ibWrap.LayoutOrder = order
			local ibBtn = Instance.new("TextButton")
			ibBtn.Size             = UDim2.new(1, 0, 0, item.Height or 44)
			ibBtn.BackgroundColor3 = VC.BgLight
			ibBtn.BorderSizePixel  = 0
			ibBtn.Text             = ""
			ibBtn.ZIndex           = 5
			ibBtn.Parent           = ibWrap
			VCorner(8, ibBtn)
			VStroke(1, VC.BorderDim, ibBtn)
			local ibImg = Instance.new("ImageLabel")
			ibImg.Size                   = UDim2.new(0.7, 0, 0.8, 0)
			ibImg.Position               = UDim2.new(0.15, 0, 0.1, 0)
			ibImg.BackgroundTransparency = 1
			ibImg.Image                  = item.Icon or ""
			ibImg.ScaleType              = Enum.ScaleType.Fit
			ibImg.ZIndex                 = 6
			ibImg.Parent                 = ibBtn
			if item.Label then
				VMakeLabel(ibWrap, item.Label,
					UDim2.new(1,0,0,18),
					UDim2.new(0,0,0,item.Height or 44),
					item.Color or VC.TextMid,
					10, Enum.Font.GothamBold,
					Enum.TextXAlignment.Center
				)
			end
			ibBtn.MouseEnter:Connect(function()    VTween(ibBtn, { BackgroundColor3 = VC.BgLighter }, 0.1) end)
			ibBtn.MouseLeave:Connect(function()    VTween(ibBtn, { BackgroundColor3 = VC.BgLight   }, 0.1) end)
			ibBtn.MouseButton1Down:Connect(function() VTween(ibBtn, { BackgroundColor3 = VC.AccentSoft }, 0.08) end)
			ibBtn.MouseButton1Up:Connect(function()   VTween(ibBtn, { BackgroundColor3 = VC.BgLight   }, 0.1)  end)
			ibBtn.MouseButton1Click:Connect(function() if item.Callback then item.Callback() end end)
			if item.Id then elements[item.Id] = ibImg end

		elseif item.Type == "separator" then
			local sep = VMakeFrame(container, UDim2.new(1,0,0,1), nil, VC.White, 0)
			sep.LayoutOrder = order
			VGradient(VC.Accent, VC.AccentPink, sep, 0)
		end
	end

	layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
		container.Size = UDim2.new(0, minWidth, 0, layout.AbsoluteContentSize.Y + 14)
	end)

	return {
		SetText  = function(_, id, v)
			local el = elements[id]
			if el and el:IsA("TextLabel") then el.Text = tostring(v) end
		end,
		SetImage = function(_, id, v)
			local el = elements[id]
			if el and el:IsA("ImageLabel") then el.Image = v end
		end,
		SetColor = function(_, id, c)
			local el = elements[id]
			if el and el:IsA("TextLabel") then el.TextColor3 = c end
		end,
		SetVisible = function(_, v) container.Visible = v end,
		Destroy    = function(_)    sg:Destroy() end,
	}
end

-- ════════════════════════════════════════════════════════════════════════════
--  MAIN CREDIT — enregistre l'onglet "Main" (Discord + liens).
--  À appeler AVANT CreateWindow, comme ShowCredit :
--      local Ui = loadstring(...)()
--      Ui:MainCredit()
--  Ne crée rien tout de suite : pose juste un flag. L'onglet est construit
--  DANS CreateWindow pour être garanti premier onglet visible.
--  opts (optionnel) : { Discord = "...", TabName = "...", Icon = "home"|0,
--                       Links = { {name=, url=}, ... } }
-- ════════════════════════════════════════════════════════════════════════════
function RayfieldLibrary:MainCredit(opts)
	_mainTabEnabled = true
	_mainTabOpts    = opts or {}
end

-- ════════════════════════════════════════════════════════════════════════════
--  SHOW CREDIT — popup anti-scam avec liens Discord / RScripts
-- ════════════════════════════════════════════════════════════════════════════
function RayfieldLibrary:ShowCredit(onClose)
	local _tempSg = Instance.new("ScreenGui")
	pcall(function() _tempSg.Parent = CoreGui end)
	local useMobile = _tempSg.AbsoluteSize.X < 1024 and _tempSg.AbsoluteSize.Y < 768
	_tempSg:Destroy()

	-- Détection executor non supporté (Xeno / Solara)
	local _execName = "Unknown"
	pcall(function() _execName = identifyexecutor() or "Unknown" end)
	local _badExec = false
	do
		local _low = string.lower(_execName)
		if string.find(_low, "xeno", 1, true) or string.find(_low, "solara", 1, true) then
			_badExec = true
		end
	end
	local warnH = _badExec and (useMobile and 64 or 72) or 0

	local BG_W = useMobile and 340 or 500
	local BG_H = (useMobile and 260 or 318) + warnH

	local ScreenGui = Instance.new("ScreenGui")
	ScreenGui.Name           = "Rayfield_Credit"
	ScreenGui.ResetOnSpawn   = false
	ScreenGui.DisplayOrder   = 9999
	local ok = pcall(function() ScreenGui.Parent = CoreGui end)
	if not ok then ScreenGui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui") end

	local bg = Instance.new("Frame")
	bg.Size             = UDim2.new(0, BG_W, 0, BG_H)
	bg.Position         = UDim2.new(0.5, -BG_W/2, 0.5, -BG_H/2)
	bg.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	bg.BorderSizePixel  = 1
	bg.Parent           = ScreenGui

	local text = Instance.new("TextLabel")
	text.Size               = UDim2.new(1, -20, 0, useMobile and 140 or 178)
	text.Position           = UDim2.new(0, 10, 0, 10)
	text.BackgroundTransparency = 1
	text.TextColor3         = Color3.fromRGB(255, 255, 255)
	text.TextWrapped        = true
	text.RichText           = true
	text.Font               = Enum.Font.GothamBold
	text.TextSize           = useMobile and 13 or 16
	text.TextYAlignment     = Enum.TextYAlignment.Top
	text.Text               = '<font color="rgb(120,200,255)">Script made by AKkiwi</font>\n\n'
		.. 'Asked for a <font color="rgb(255,90,90)">key</font>? You got <font color="rgb(255,90,90)">SCAMMED.</font>\n'
		.. '<font color="rgb(80,220,120)">All my scripts are FREE &amp; KEYLESS — always.</font>\n\n'
		.. '<font color="rgb(255,200,80)">Join the Discord for more scripts &amp; updates!</font>\n'
		.. '<font color="rgb(200,160,255)">💡 I make custom scripts on request — for free.</font>\n'
		.. '<font color="rgb(185,150,255)">💬 Join the Discord below</font> 👇'
	text.Parent             = bg

	if _badExec then
		local warnLabel = Instance.new("TextLabel")
		warnLabel.Size                   = UDim2.new(1, -20, 0, warnH - 6)
		warnLabel.Position               = UDim2.new(0, 10, 0, useMobile and 154 or 192)
		warnLabel.BackgroundColor3       = Color3.fromRGB(40, 10, 10)
		warnLabel.BackgroundTransparency = 0.2
		warnLabel.BorderSizePixel        = 0
		warnLabel.TextColor3             = Color3.fromRGB(255, 90, 90)
		warnLabel.TextWrapped            = true
		warnLabel.Font                   = Enum.Font.GothamBold
		warnLabel.TextSize               = useMobile and 11 or 13
		warnLabel.Text                   = "⚠️ You are using " .. _execName .. ".\nThis executor is NOT supported by my scripts and may cause errors.\nJoin the Discord below to find a working executor."
		warnLabel.Parent                 = bg
	end

	local discordBtn = Instance.new("TextButton")
	discordBtn.Size             = UDim2.new(1, -20, 0, 34)
	discordBtn.Position         = UDim2.new(0, 10, 0, (useMobile and 158 or 196) + warnH)
	discordBtn.BackgroundColor3 = Color3.fromRGB(20, 22, 40)
	discordBtn.TextColor3       = Color3.fromRGB(150, 165, 255)
	discordBtn.Font             = Enum.Font.GothamBold
	discordBtn.TextSize         = useMobile and 13 or 15
	discordBtn.BorderSizePixel  = 0
	discordBtn.Text             = "🎉 discord.gg/ddu37DWPJn — JOIN US! (click to copy)"
	discordBtn.Parent           = bg
	discordBtn.MouseButton1Click:Connect(function()
		pcall(setclipboard, "https://discord.gg/ddu37DWPJn")
		discordBtn.Text = "✅ Link copied — see you there!"
		task.wait(2)
		discordBtn.Text = "🎉 discord.gg/ddu37DWPJn — JOIN US! (click to copy)"
	end)

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size             = UDim2.new(1, -20, 0, 34)
	closeBtn.Position         = UDim2.new(0, 10, 0, (useMobile and 200 or 238) + warnH)
	closeBtn.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	closeBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
	closeBtn.Font             = Enum.Font.GothamBold
	closeBtn.TextSize         = useMobile and 13 or 15
	closeBtn.BorderSizePixel  = 0
	closeBtn.Text             = "Got it — Close"
	closeBtn.Parent           = bg
	closeBtn.MouseButton1Click:Connect(function()
		ScreenGui:Destroy()
		if onClose then onClose() end
	end)
end

-- ════════════════════════════════════════════════════════════════════════════
--  DESTROY ALL — détruit tous les ScreenGui Rayfield (pour re-injection)
-- ════════════════════════════════════════════════════════════════════════════
function RayfieldLibrary:DestroyAll()
	local prefix = "Rayfield"
	local function cleanIn(parent)
		for _, child in ipairs(parent:GetChildren()) do
			if child:IsA("ScreenGui") and child.Name:sub(1, #prefix) == prefix then
				child:Destroy()
			end
		end
	end
	pcall(function() cleanIn(CoreGui) end)
	pcall(function() cleanIn(Players.LocalPlayer.PlayerGui) end)
end

-- ════════════════════════════════════════════════════════════════════════════
--  SET SCRIPT NAME + ANALYTICS VOIDUI
-- ════════════════════════════════════════════════════════════════════════════
local _voidScriptName = "Rayfield"
local _voidSessionId  = nil

function RayfieldLibrary:SetScriptName(name)
	_voidScriptName = name or "Rayfield"
	_cfgShare.script = _voidScriptName
end

-- Change le texte de la topbar à chaud (Topbar est un upvalue module-level).
function RayfieldLibrary:SetTitle(text)
	pcall(function()
		Topbar.Title.Text = text or "RayVoid"
	end)
end

function RayfieldLibrary:SetPremium(val)  -- ← ajouter ici
    _voidIsPremium = val == true
end

do
	local VOID_BASE_URL = "https://akkiwi.com"
	local _httpFn = nil
	local function _getHttp()
		if _httpFn then return _httpFn end
		if syn and syn.request then _httpFn = syn.request
		elseif http and http.request then _httpFn = http.request
		elseif http_request then _httpFn = http_request
		elseif request then _httpFn = request end
		return _httpFn
	end
	local function _getExecName()
		local name = "Unknown"
		pcall(function()
			local n = identifyexecutor()
			name = n or "Unknown"
		end)
		return name
	end


	local function _voidPost(endpoint, payload)
		local fn = _getHttp()
		if not fn then return nil end
		local ok, res = pcall(fn, {
			Url     = VOID_BASE_URL .. endpoint,
			Method  = "POST",
			Headers = { ["Content-Type"] = "application/json" },
			Body    = HttpService:JSONEncode(payload),
		})
		if not ok then return nil end
		local parsed
		pcall(function() parsed = HttpService:JSONDecode(res.Body or res) end)
		return parsed
	end

	

	task.spawn(function()
		task.wait(3)
		local player = Players.LocalPlayer

		local function _startSession()
		local gameName = "Unknown"
		    pcall(function()
		        gameName = game:GetService("MarketplaceService"):GetProductInfo(game.PlaceId).Name
		    end)

			return _voidPost("/session/start", {
			        user_id   = tostring(player.UserId),
			        username  = player.Name,
			        place_id  = tostring(game.PlaceId),
			        game_id   = tostring(game.GameId),
			        game_name = gameName,
			        job_id    = tostring(game.JobId),
			        script    = _voidScriptName,
			        executor  = _getExecName(),
			    })
end


		local res = _startSession()
		if not res or not res.session_id then return end
		_voidSessionId = res.session_id

		task.spawn(function()
			while task.wait(600) do
				if not _voidSessionId then break end
				local hb = _voidPost("/heartbeat", { session_id = _voidSessionId })
				if hb and hb.reregister then
					local newRes = _startSession()
					if newRes and newRes.session_id then
						_voidSessionId = newRes.session_id
					end
				end
			end
		end)

		local function _endSession()
			if _voidSessionId then
				_voidPost("/session/end", { session_id = _voidSessionId })
				_voidSessionId = nil
			end
		end

		game:BindToClose(_endSession)
		player.AncestryChanged:Connect(function()
			if not player.Parent then _endSession() end
		end)
	end)
end

-- ════════════════════════════════════════════════════════════════════════════
--  NOTIFY TYPÉ — wrapper pour compatibilité format VoidUI
-- ════════════════════════════════════════════════════════════════════════════
local _rayfieldNotifyOriginal = RayfieldLibrary.Notify

function RayfieldLibrary:Notify(cfg)
	cfg = cfg or {}
	if cfg.Type and cfg.Message then
		local typeToImage = {
			success = "rbxassetid://7072725342",
			warning = "rbxassetid://7072725252",
			error   = "rbxassetid://7072725185",
			info    = "rbxassetid://7072725318",
		}
		local translated = {
			Title    = cfg.Title    or "Notification",
			Content  = cfg.Message,
			Duration = cfg.Duration or 3,
			Image    = typeToImage[cfg.Type] or typeToImage["info"],
			Force    = cfg.Force,
		}
		return _rayfieldNotifyOriginal(self, translated)
	end
	return _rayfieldNotifyOriginal(self, cfg)
end

return RayfieldLibrary