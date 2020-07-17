#pragma semicolon 1
#pragma semicolon 1
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <smlib>

#pragma newdecls required
#include <smrpg>
#include <smrpg_effects>

#define UPGRADE_SHORTNAME "guardian_angel"

ConVar g_hCVAliveChance;
ConVar g_hCVAliveHp;

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Guardian Angel",
	author = "LongPC",
	description = "Guardian Angel upgrade for SM:RPG. Keep player alive when received deady shot.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	HookEvent("player_death", Event_PlayerDeath, EventHookMode_Pre);
	
	LoadTranslations("smrpg_stock_upgrades.phrases");
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
		SMRPG_RegisterUpgradeType("Guardian Angel", UPGRADE_SHORTNAME, "Keep player alive when received deady shot.", 0, true, 5, 80, 80);		
		g_hCVAliveChance = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_ga_percent", "0.05", "Chance player can alive when deady shot", _, true, 0.0);
		g_hCVAliveHp = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_ga_hp", "1.0", "Hp player remain when ga active", _, true, 0.0);
	}
}

public Action Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker", 0));
	int victim = GetClientOfUserId(GetEventInt(event, "userid", 0));
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(victim) && SMRPG_IgnoreBots())
		return Plugin_Continue;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	if (GetURandomFloat() > iLevel * g_hCVAliveChance.FloatValue)
		return Plugin_Continue;
	SetEntityHealth(victim, g_hCVAliveHp.IntValue);
	if(SMRPG_IsClientBurning(victim))
		SMRPG_ExtinguishClient(victim);
	if(SMRPG_IsClientFrozen(victim))
		SMRPG_UnfreezeClient(victim);
	SMRPG_ResetClientLaggedMovement(victim, LMT_Slower);
	Client_PrintToChatAll(false, "{RB}%N{N} nhân phẩm tốt chạy hiệu ứng {B}%s từ chối tử thần{N}, xóa mọi hiệu ứng bất lợi", victim, UPGRADE_SHORTNAME);
	return Plugin_Handled;
}

public void SMRPG_TranslateUpgrade(int client, const char[] shortname, TranslationType type, char[] translation, int maxlen)
{
	if(type == TranslationType_Name)
		Format(translation, maxlen, "%T", UPGRADE_SHORTNAME, client);
	else if(type == TranslationType_Description)
	{
		char sDescriptionKey[MAX_UPGRADE_SHORTNAME_LENGTH+12] = UPGRADE_SHORTNAME;
		StrCat(sDescriptionKey, sizeof(sDescriptionKey), " description");
		Format(translation, maxlen, "%T", sDescriptionKey, client);
	}
}
