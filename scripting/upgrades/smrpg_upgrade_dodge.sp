#pragma semicolon 1
#include <sourcemod>
#include <sdkhooks>
#include <smlib/clients>

#pragma newdecls required
#include <smrpg>


#define UPGRADE_SHORTNAME "dodge"

ConVar g_hCVDefaultPercent;


public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Dodge",
	author = "LongPC",
	description = "Dodge upgrade for SM:RPG. Give player a chance to dodge attack dame.",
	version = SMRPG_VERSION,
	url = "http://www.wcfan.de/"
}

public void OnPluginStart()
{
	LoadTranslations("smrpg_stock_upgrades.phrases");
	
	// Account for late loading
	for(int i=1;i<=MaxClients;i++)
	{
		if(IsClientInGame(i))
			OnClientPutInServer(i);
	}
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
		SMRPG_RegisterUpgradeType("Dodge", UPGRADE_SHORTNAME, "Give player a chance to dodge attack dame.", 0, true, 5, 40, 40);
		SMRPG_SetUpgradeTranslationCallback(UPGRADE_SHORTNAME, SMRPG_TranslateUpgrade);
		g_hCVDefaultPercent = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "smrpg_miss_percent", "0.05", "Percentage of dodge butlet", _, true, 0.0);
	}
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
}

public void OnMapStart()
{
}

/**
 * SM:RPG Upgrade callbacks
 */

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

/**
 * Hook callbacks
 */
public Action Hook_OnTakeDamage(int victim, int &attacker, int &inflictor, float &damage, int &damagetype, int &weapon, float damageForce[3], float damagePosition[3], int damagecustom)
{
	if(attacker <= 0 || attacker > MaxClients || victim <= 0 || victim > MaxClients)
		return Plugin_Continue;
	
	if(!SMRPG_IsEnabled())
		return Plugin_Continue;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return Plugin_Continue;
	
	// Are bots allowed to use this upgrade?
	if(IsFakeClient(attacker) && SMRPG_IgnoreBots())
		return Plugin_Continue;
	
	// Ignore team attack if not FFA
	if(!SMRPG_IsFFAEnabled() && GetClientTeam(attacker) == GetClientTeam(victim))
		return Plugin_Continue;
	
	if(!SMRPG_RunUpgradeEffect(victim, UPGRADE_SHORTNAME, attacker))
		return Plugin_Continue; // Some other plugin doesn't want this effect to run

	int iLevel = SMRPG_GetClientUpgradeLevel(victim, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return Plugin_Continue;
	
	char sClassname[32] = "default";
	GetEntityClassname(inflictor, sClassname, sizeof(sClassname));
	if (StrEqual(sClassname, "entityflame", false)) {
		return Plugin_Continue;
	}
	int iWeapon = inflictor;
	if(inflictor > 0 && inflictor <= MaxClients)
		iWeapon = Client_GetActiveWeapon(inflictor);
	
	if(iWeapon == -1)
		return Plugin_Continue;
	
	char sWeapon[256];
	GetEntityClassname(iWeapon, sWeapon, sizeof(sWeapon));

	if (StrContains(sWeapon, "hegrenade") != -1) {
		return Plugin_Continue;
	}
	
	if (GetURandomFloat() > g_hCVDefaultPercent.FloatValue * iLevel)
		return Plugin_Continue;

	damage = 0.0;
	//Client_PrintToChatAll(false, "{RB}%N{N} nhân phẩm tốt chạy hiệu ứng {B}%s (né){N}", victim, UPGRADE_SHORTNAME);
	return Plugin_Changed;
}
