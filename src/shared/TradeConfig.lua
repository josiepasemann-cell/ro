--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Module: TradeConfig
	Responsibility:
		Single source of truth for the 2-player creature trade (GDD section 7
		"Trading system"). Pure data, read by TradeService (authoritative) and
		TradeUIController (display only). Creatures only - no Robux, no
		currencies.

	Rojo mount point:
		src/shared/TradeConfig.lua -> ReplicatedStorage.TradeConfig
]]

local TradeConfig = {}

-- // Eligibility ----------------------------------------------------------------
TradeConfig.MIN_LEVEL = 5 -- both players need this player level
TradeConfig.MAX_OFFER = 4 -- creatures per side
TradeConfig.COOLDOWN_SECONDS = 60 -- after a completed trade (uses persisted TradeState.LastTradeAt)

-- // Requests ------------------------------------------------------------------
TradeConfig.REQUEST_TIMEOUT_SECONDS = 30
TradeConfig.REQUEST_SEND_COOLDOWN_SECONDS = 4 -- min. gap between two requests of one player
TradeConfig.REQUEST_DECLINE_COOLDOWN_SECONDS = 20 -- same sender -> same target after a decline/expiry

-- // Trade window ----------------------------------------------------------------
TradeConfig.CONFIRM_COUNTDOWN_SECONDS = 5 -- Confirm unlocks this long after both are Ready
TradeConfig.TRADE_IDLE_TIMEOUT_SECONDS = 180 -- no change/ready/confirm for this long -> cancel
TradeConfig.START_DISTANCE_STUDS = 60 -- max. distance between the two characters to start
TradeConfig.MAX_DISTANCE_STUDS = 90 -- trade is cancelled when the players move further apart
TradeConfig.MONITOR_INTERVAL_SECONDS = 0.5

-- // Hub dock ----------------------------------------------------------------------
TradeConfig.DOCK_MODEL_NAME = "TradeDock" -- assets/models/hub/TidalMarketHub.lua, Interactable = "Trade"
TradeConfig.DOCK_PROMPT_NAME = "TradeDockPrompt"

-- // Reasons (server -> client, mapped to friendly English text by the UI) -----------------
TradeConfig.REASON_TEXT = {
	NotLoaded = "Your data is still loading. Try again in a moment.",
	TargetNotLoaded = "That player is still loading.",
	LevelTooLow = "You need level %d to trade.",
	TargetLevelTooLow = "That player needs level %d to trade.",
	Cooldown = "You can trade again in %d seconds.",
	TargetCooldown = "That player has to wait a bit before trading again.",
	Busy = "You already have a trade or a request open.",
	TargetBusy = "That player is busy right now.",
	TooFar = "You are too far away from that player.",
	NoCharacter = "Your character is not ready.",
	UnknownPlayer = "That player is not in this server.",
	Self = "You cannot trade with yourself.",
	RateLimited = "Slow down a little.",
	RequestCooldown = "Please wait a moment before sending another request.",
	DeclinedRecently = "That player said no a moment ago. Try again soon.",
	InRaid = "Trading is not possible during a raid.",
	TargetInRaid = "That player is in a raid right now.",
	RequestExpired = "That request has expired.",
	Declined = "The trade request was declined.",
	RequestTimeout = "The trade request timed out.",
	PartnerLeft = "Your trade partner left the game.",
	MovedAway = "Trade cancelled - you moved too far apart.",
	Died = "Trade cancelled - a player was defeated.",
	Cancelled = "The trade was cancelled.",
	CancelledByPartner = "Your partner cancelled the trade.",
	IdleTimeout = "Trade cancelled - nothing happened for a while.",
	InvalidOffer = "That offer is not allowed.",
	TooManyCreatures = "You can offer up to %d creatures.",
	CreatureLocked = "That creature cannot be traded right now.",
	BuddyLocked = "Your buddy creature cannot be traded.",
	OfferChanged = "The offer changed. Check it again.",
	NotReady = "Both players must be ready first.",
	ConfirmLocked = "Confirm unlocks in a moment.",
	TradeFailed = "The trade could not be completed. Nothing was changed.",
	Completed = "Trade complete!",
	NoTrade = "There is no open trade.",
	ServerShuttingDown = "The server is shutting down.",
} :: { [string]: string }

return TradeConfig
