/**
 * SM:RPG Poison Smoke Upgrade
 * Damages players inside the smoke of a smoke grenade.
 */
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma newdecls required
#include <smrpg>

#define UPGRADE_SHORTNAME "poisonsmoke"

enum GrenadeInfo {
	GR_userid,
	GR_team,
	GR_particle,
	Handle:GR_removeTimer,
	Handle:GR_damageTimer,
};

ArrayList g_hThrownGrenades;

ConVar g_hCVFriendlyFire;
ConVar g_hCVIgnoreFriendlyFire;
ConVar g_hCVBaseDamage;
ConVar g_hCVIncDamage;
ConVar g_hCVInterval;

bool g_bInCheckDamage;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Poison Smoke",
	author = "Jannik \"Peace-Maker\" Hartung",
	description = "Poison Smoke upgrade for SM:RPG. Damages players standing inside the smoke of a smoke grenade.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	EngineVersion engine = GetEngineVersion();
	if(engine != Engine_CSS)
	{
		Format(error, err_max, "This plugin is for use in Counter-Strike games only. Bad engine version %d.", engine);
		return APLRes_SilentFailure;
	}
	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	g_hThrownGrenades = new ArrayList(view_as<int>(GrenadeInfo));
	
	// To change the weapon icon from some skull to a grenade!
	HookEvent("player_death", Event_OnPlayerDeath, EventHookMode_Pre);
	
	HookEvent("round_start", Event_OnResetSmokes);
	HookEvent("round_end", Event_OnResetSmokes);
	// Hook events
	HookEvent("smokegrenade_detonate", smokegrenade_detonate);
	
	g_hCVFriendlyFire = FindConVar("mp_friendlyfire");
}

public void OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
	// Register this upgrade in SM:RPG
	if(StrEqual(name, "smrpg"))
	{
		// Register the upgrade type.
		SMRPG_RegisterUpgradeType("Poison Smoke", UPGRADE_SHORTNAME, "Damages players standing inside the smoke of a smoke grenade.", 0, true, 10, 15, 10);
		
		// If you want to translate the upgrade name and description into the client languages, register this callback!
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		
		SMRPG_SetUpgradeDefaultCosmeticEffect(UPGRADE_SHORTNAME, SMRPG_FX_Visuals, true);
		
		// Create your convars through the SM:RPG core. That way they are added to your upgrade's own config file in cfg/sourcemod/smrpg/smrpg_upgrade_example.cfg!
		g_hCVIgnoreFriendlyFire = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_ignoreff", "0", "Ignore the setting of mp_friendlyfire and don't allow team damage by poison smoke at all?", _, true, 0.0, true, 1.0);
		g_hCVBaseDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_basedamage", "3", "The minimum damage the poison smoke inflicts.", _, true, 0.0);
		g_hCVIncDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_incdamage", "2", "How much damage multiplied by the upgrade level should we add to the base damage?", _, true, 1.0);
		g_hCVInterval = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_poisonsmoke_damage_interval", "1", "Deal damage every x seconds.", _, true, 0.1);
	}
}

public void OnMapEnd()
{
	// No need to close the timers manually, because they're closed automagically on map end.
	g_hThrownGrenades.Clear();
}

/**
 * Event callbacks
 */
// Change the killicon to a grenade. Smokes don't have an own icon, so we'll use the flashbang!
public Action Event_OnPlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	char sWeapon[64];
	event.GetString("weapon", sWeapon, sizeof(sWeapon));
	if(StrEqual(sWeapon, "env_particlesmokegrenade"))
	{
		event.SetString("weapon", "flashbang");
	}
	return Plugin_Continue;
}

public void Event_OnResetSmokes(Event event, const char[] name, bool dontBroadcast)
{
	int iSize = g_hThrownGrenades.Length;
	int iGrenade[GrenadeInfo];
	for(int i=0;i<iSize;i++)
	{
		g_hThrownGrenades.GetArray(i, iGrenade[0], view_as<int>(GrenadeInfo));
		
		if(iGrenade[GR_removeTimer] != null)
			delete iGrenade[GR_removeTimer];
		if(!g_bInCheckDamage && iGrenade[GR_damageTimer] != null)
		{
			delete iGrenade[GR_damageTimer];
		}
	}
	g_hThrownGrenades.Clear();
	
	if(g_bInCheckDamage)
		g_bInCheckDamage = false;
}

/**
 * SM:RPG Upgrade callbacks
 */
// The core wants to display your upgrade somewhere. Translate it into the clients language!
public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	// Easy pattern is to use the shortname of your upgrade in the translation file
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	// And "shortname description" as phrase in the translation file for the description.
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}

// public void OnEntityCreated(int entity, const char[] classname)
// {
// 	if(StrEqual(classname, "smokegrenade_projectile", false))
// 	{
// 		SDKHook(entity, SDKHook_Spawn, Hook_OnSpawnProjectile);
// 	}
	
// 	// CS:S doesn't use the EffectDispatch ParticleEffect route, but creates such an entity instead.
// 	if(StrEqual(classname, "env_particlesmokegrenade", false))
// 	{
// 		SDKHook(entity, SDKHook_Spawn, Hook_OnSpawnParticles);
// 	}
// }

public void smokegrenade_detonate(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(client == INVALID_ENT_REFERENCE || !IsClientInGame(client))
		return;
	
	if(!SMRPG_CanRunEffectOnClient(client))
		return;
	
	int iGrenade[GrenadeInfo];
	iGrenade[GR_userid] = GetClientUserId(client);
	iGrenade[GR_team] = GetClientTeam(client);
	iGrenade[GR_particle] = INVALID_ENT_REFERENCE;
	iGrenade[GR_removeTimer] = null;
	iGrenade[GR_damageTimer] = null;

	// Get coordinates of this event
	float a[3], b[3];
	a[0] = GetEventFloat(event, "x");
	a[1] = GetEventFloat(event, "y");
	a[2] = GetEventFloat(event, "z");
	
	int checkok = 0;
	int ent = -1;
	
	// List all entitys by classname
	while((ent = FindEntityByClassname(ent, "env_particlesmokegrenade")) != -1)
	{
		// Get entity coordinates
		GetEntPropVector(ent, Prop_Send, "m_vecOrigin", b);
		
		// If entity same coordinates some event coordinates
		if(a[0] == b[0] && a[1] == b[1] && a[2] == b[2])
		{		
			checkok = 1;
			break;
		}
	}
	if (checkok) {
		int entityRef = EntIndexToEntRef(ent);
		iGrenade[GR_particle] = entityRef;
		float fFadeStartTime = GetEntPropFloat(ent, Prop_Send, "m_FadeStartTime");
		float fFadeEndTime = GetEntPropFloat(ent, Prop_Send, "m_FadeEndTime");
		
		// Stop dealing damage when the smoke starts to vanish.
		iGrenade[GR_removeTimer] = CreateTimer(fFadeStartTime+(fFadeEndTime-fFadeStartTime)/2.5, Timer_StopDamage, entityRef, TIMER_FLAG_NO_MAPCHANGE);
		// Deal damage to anyone walking into the smoke
		iGrenade[GR_damageTimer] = CreateTimer(g_hCVInterval.FloatValue, Timer_CheckDamage, entityRef, TIMER_FLAG_NO_MAPCHANGE|TIMER_REPEAT);
	}
	g_hThrownGrenades.PushArray(iGrenade[0], view_as<int>(GrenadeInfo));

}

/**
 * Timer callbacks
 */
// Remove the poison effect, 2 seconds before the smoke is completely vanished
public Action Timer_StopDamage(Handle timer, any entityref)
{
	// Get the grenade array with this entity index
	int iSize = g_hThrownGrenades.Length;
	int iGrenade[GrenadeInfo];
	for(int i=0; i<iSize; i++)
	{
		g_hThrownGrenades.GetArray(i, iGrenade[0], view_as<int>(GrenadeInfo));
		// This is the right grenade
		// Remove it
		if(iGrenade[GR_particle] == entityref)
		{
			delete iGrenade[GR_damageTimer];
			
			g_hThrownGrenades.Erase(i);
			break;
		}
	}
	
	return Plugin_Stop;
}

// Do damage every seconds to players in the smoke
public Action Timer_CheckDamage(Handle timer, any entityref)
{
	int entity = EntRefToEntIndex(entityref);
	if(entity == INVALID_ENT_REFERENCE)
		return Plugin_Continue;
	
	// Get the grenade array with this entity index
	int iSize = GetArraySize(g_hThrownGrenades);
	int iGrenade[GrenadeInfo];
	bool bFound;
	for(int i=0; i<iSize; i++)
	{
		g_hThrownGrenades.GetArray(i, iGrenade[0], view_as<int>(GrenadeInfo));
		if(iGrenade[GR_particle] == entityref)
		{
			bFound = true;
			break;
		}
	}
	
	// The particles were removed already.
	if(!bFound)
		return Plugin_Continue;
	
	// Don't do anything, if the client who's thrown the grenade left.
	int client = GetClientOfUserId(iGrenade[GR_userid]);
	if(!client)
		return Plugin_Continue;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	// We're dealing damage now. If we kill the last person in the team and the round ends, this timer will be stopped while we're still in here.
	// We can't have an invalid timer handle in the timer's callback, so don't close it.
	g_bInCheckDamage = true;
	
	float fDamage = g_hCVBaseDamage.FloatValue + g_hCVIncDamage.FloatValue * float(iLevel);
	
	float fParticleOrigin[3], fPlayerOrigin[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", fParticleOrigin);
	
	bool bFriendlyFire = g_hCVFriendlyFire.BoolValue;
	bool bIgnoreFriendlyFire = g_hCVIgnoreFriendlyFire.BoolValue;
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i) && IsPlayerAlive(i) && !IsClientObserver(i) && (SMRPG_IsFFAEnabled() || (bFriendlyFire && !bIgnoreFriendlyFire || GetClientTeam(i) != iGrenade[GR_team])))
		{
			GetClientAbsOrigin(i, fPlayerOrigin);
			if(GetVectorDistance(fParticleOrigin, fPlayerOrigin) <= 220)
				SDKHooks_TakeDamage(i, iGrenade[GR_particle], client, fDamage, DMG_DIRECT, -1, NULL_VECTOR, fParticleOrigin);
		}
	}
	
	// round_end was fired during timer execution. stop ourself now.
	if(!g_bInCheckDamage)
		return Plugin_Stop;
	
	g_bInCheckDamage = false;
	
	return Plugin_Continue;
}

stock bool SMRPG_CanRunEffectOnClient(int client)
{
	// SM:RPG is disabled?
	if(!SMRPG_IsEnabled())
		return false;
	
	// The upgrade is disabled completely?
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return false;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return false;
	
	// Player didn't buy this upgrade yet.
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return false;
	
	return true;
}