#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <codmod>

#define PLUGIN_NAME "Call of Duty: Umiejętności"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "KarajuSs"
#define PLUGIN_DESCRIPTION "Ułatwia dodawanie umiejętności do klasy/perków oraz skraca niepotrzebnie powtarzający się kod w nich"
#define PLUGIN_URL "http://steamcommunity.com/id/karajussg"

#define MAX_WEAPONS (view_as<int>(CSWeapon_MAX_WEAPONS_NO_KNIFES))

int vis = 255;
int umiejetnosc[MAXPLAYERS+1][MAX_SKILLI],
	szansa_na_zabicie[MAXPLAYERS+1][MAX_WEAPONS+1],
	glowID[MAXPLAYERS+1], offset_thrower,
	zatruty[MAXPLAYERS+1];
float wieksze_obrazenia[MAXPLAYERS+1][MAX_WEAPONS+1],
	przelicznik_int[MAXPLAYERS+1],
	grawitacja_gracza[MAXPLAYERS+1],
	time_gracza[MAXPLAYERS+1];

Handle odmrozenie[MAXPLAYERS+1],
	zatrucie[MAXPLAYERS+1];

public Plugin:myinfo = {
	name = PLUGIN_NAME,
	author = PLUGIN_AUTHOR,
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = PLUGIN_URL
};

char nazwy_broni[][] = {
	"weapon_glock", "weapon_usp_silencer", "weapon_hkp2000", "weapon_p250", "weapon_tec9", "weapon_fiveseven", "weapon_cz75a", "weapon_deagle",
	"weapon_revolver", "weapon_elite", "weapon_m4a1_silencer", "weapon_ak47", "weapon_awp", "weapon_m4a1", "weapon_negev", "weapon_famas",
	"weapon_aug", "weapon_p90", "weapon_nova", "weapon_xm1014", "weapon_mag7", "weapon_mac10", "weapon_mp7", "weapon_mp9", "weapon_bizon",
	"weapon_ump45", "weapon_galilar", "weapon_ssg08", "weapon_sg556", "weapon_m249", "weapon_scar20", "weapon_g3sg1", "weapon_sawedoff",
	"weapon_mp5sd"
};
int naboje_broni[][2] = {
	{20, 120}, {12, 24}, {13, 52}, {13, 26}, {32, 120}, {20, 100}, {12, 12}, {7, 35}, {8, 8}, {30, 120}, {20, 40}, {30, 90}, {10, 30}, {30, 90}, {150, 200}, {25, 90}, {30, 90},
	{50, 100}, {8, 32}, {7, 32}, {5, 32}, {30, 100}, {30, 120}, {30, 120}, {64, 120}, {25, 100}, {35, 90}, {10, 90}, {30, 90}, {100, 200}, {20, 90}, {20, 90}, {7, 32}, {30, 120}
};

char modele_postaci[][] = {
	"models/player/ctm_fbi.mdl", "models/player/ctm_gign.mdl", "models/player/ctm_gsg9.mdl", "models/player/ctm_sas.mdl", "models/player/ctm_st6.mdl",
	"models/player/tm_anarchist.mdl", "models/player/tm_phoenix.mdl", "models/player/tm_pirate.mdl", "models/player/tm_balkan_variantA.mdl", "models/player/tm_leet_variantA.mdl"
};

public OnPluginStart() {
	CreateConVar(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);
}

public void OnMapStart() {
	PrecacheSound("physics/glass/glass_strain2.wav", true);
	PrecacheSound("physics/glass/glass_bottle_break2.wav", true);

	offset_thrower = FindSendPropInfo("CBaseGrenade", "m_hThrower");
	if (offset_thrower == -1) {
		SetFailState("Can't find m_hThrower offset");
	}

	// Spis wydarzeń
	//HookEvent("player_spawn", Odrodzenie);
	HookEvent("player_death", SmiercGracza);
	HookEvent("smokegrenade_detonate", ZdetonowanyDymny);
	HookEvent("bullet_impact", NieskonczonyMagazynek);
	HookEvent("player_blind", PlayerBlind, EventHookMode_Pre);

	// Ciche kroki
	AddNormalSoundHook(CicheKroki);

	for(new i = 0; i < sizeof(modele_postaci); i ++)
		PrecacheModel(modele_postaci[i]);
}

public void OnMapEnd() {
	for(int i = 1; i <= MaxClients; i++) {
		odmrozenie[i] = null;
	}
}

public OnClientPutInServer(client) {
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKHook(client, SDKHook_SpawnPost, Spawn_Post);
	SDKHook(client, SDKHook_PreThink, Think_Post);
	SDKHook(client, SDKHook_PreThinkPost, Think_Post);
	SDKHook(client, SDKHook_PostThink, Think_Post);
	SDKHook(client, SDKHook_PostThinkPost, Think_Post);

	if(!IsFakeClient(client))
		SendConVarValue(client, FindConVar("sv_footsteps"), "0");

	WyzerujSkill(client);
	WyzerujZabojstwa(client);
	WyzerujObrazenia(client);
	WyzerujObrazeniaZInt(client);

	time_gracza[client] = 0.0;
}
public OnClientDisconnect(client) {
	SDKUnhook(client, SDKHook_OnTakeDamage, OnTakeDamage);
	SDKUnhook(client, SDKHook_SpawnPost, Spawn_Post);
	SDKUnhook(client, SDKHook_PreThink, Think_Post);
	SDKUnhook(client, SDKHook_PreThinkPost, Think_Post);
	SDKUnhook(client, SDKHook_PostThink, Think_Post);
	SDKUnhook(client, SDKHook_PostThinkPost, Think_Post);

	if(odmrozenie[client] != null) {
		KillTimer(odmrozenie[client]);
		odmrozenie[client] = null;
	}
	if (zatrucie[client] != null) {
		KillTimer(zatrucie[client]);
		zatrucie[client] = null;
	}
}
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int errorLen) {
	RegPluginLibrary("codmod_umiejetnosci");

	// Natywy
	CreateNative("cod_set_skill", nat_UstawSkill);
	CreateNative("cod_set_gravity", nat_UstawGrawitacje);
	CreateNative("cod_set_weapon_chance", nat_UstawZabojstwa);
	CreateNative("cod_set_more_damage", nat_UstawObrazenia);
	CreateNative("cod_set_more_damage_int", nat_UstawObrazeniaZInt);

	return APLRes_Success;
}

public int nat_UstawSkill(Handle plugin, int paramsNum) {
	return UstawSkill(GetNativeCell(1), GetNativeCell(2), GetNativeCell(3));
}
public int nat_UstawGrawitacje(Handle plugin, int paramsNum) {
	return UstawGrawitacje(GetNativeCell(1), view_as<float>(GetNativeCell(2)));
}
public int nat_UstawZabojstwa(Handle plugin, int paramsNum) {
	return UstawZabojstwa(GetNativeCell(1), view_as<int>(GetNativeCell(2)), GetNativeCell(3));
}
public int nat_UstawObrazenia(Handle plugin, int paramsNum) {
	return UstawObrazenia(GetNativeCell(1), view_as<int>(GetNativeCell(2)), GetNativeCell(3));
}
public int nat_UstawObrazeniaZInt(Handle plugin, int paramsNum) {
	return UstawObrazeniaZInt(GetNativeCell(1), view_as<int>(GetNativeCell(2)), GetNativeCell(3), GetNativeCell(4));
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3]) {
	if(!IsValidClient(client)|| !IsPlayerAlive(client))
		return Plugin_Continue;
	if(GetEntProp(client, Prop_Send, "m_nWaterLevel") > 1
			|| GetEntityMoveType(client) & MOVETYPE_LADDER) {
		return Plugin_Continue;
	}
	new flags = GetEntityFlags(client);

	if(umiejetnosc[client][multi_skok]) {
		static lastButtons[MAXPLAYERS+1];
		static jumps[MAXPLAYERS+1];

		GetClientEyeAngles(client, angles);

		if ((buttons & IN_JUMP) && !(flags & FL_ONGROUND) && !(lastButtons[client] & IN_JUMP) && jumps[client] > 0) {
			jumps[client] --;

			GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);
			vel[2] = 320.0;
			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
		} else if (flags & FL_ONGROUND) {
			jumps[client] = 0;
			if(umiejetnosc[client][multi_skok])
				jumps[client] += umiejetnosc[client][multi_skok];
		}
		lastButtons[client] = buttons;
	}
	
	if(umiejetnosc[client][dlugi_skok]) {
		float gametime = GetGameTime();
		if((buttons & IN_DUCK) && (buttons & IN_JUMP) && (flags & FL_ONGROUND) && (gametime > time_gracza[client]+4.0)) {
			int moc = umiejetnosc[client][dlugi_skok]+RoundFloat(cod_get_user_maks_intelligence(client)*4.0);
			GetClientEyeAngles(client, angles);

			angles[0] *= -1.0; 
			angles[0] = DegToRad(angles[0]); 
			angles[1] = DegToRad(angles[1]); 

			vel[0] = Cosine(angles[0]) * Cosine(angles[1]) * moc;
			vel[1] = Cosine(angles[0]) * Sine(angles[1]) * moc;
			vel[2] = 265.0;

			TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vel);
			time_gracza[client] = gametime;
		}
	}

	if(umiejetnosc[client][niewidka])
		StartRender(client);
	if(umiejetnosc[client][niewidka_noz]) {
		char weapon[32];
		GetClientWeapon(client, weapon, sizeof(weapon));
		if((StrEqual(weapon, "weapon_bayonet") || StrContains(weapon, "weapon_knife", false) != -1))
			StartRender(client);
		else
			StopRender(client);
	}
	if(umiejetnosc[client][niewidka_kucanie]) {
		if((buttons & IN_DUCK))
			StartRender(client);
		else
			StopRender(client);
	}
	if(umiejetnosc[client][niewidka_kucanie_noz]) {
		if((buttons & IN_DUCK) && GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
			StartRender(client);
		else
			StopRender(client);
	}

	if(umiejetnosc[client][autobh]) {
		if(buttons & IN_JUMP) {
			if(!(GetEntityFlags(client) & (FL_WATERJUMP | FL_ONGROUND)))
				buttons &= ~IN_JUMP;
		}
	}

	return Plugin_Continue;
}

public Action OnTakeDamage(int client, int &attacker, int &inflictor, float &damage, int &damageType) {
	if(!IsValidClient(attacker) || !IsValidClient(client) || !IsClientInGame(attacker) || !IsPlayerAlive(attacker) || GetClientTeam(attacker) == GetClientTeam(client))
		return Plugin_Continue;

	int weapon;
	int weaponID;
	CSWeaponID csWeaponID;

	if(weapon == -1) {
		if(inflictor > MAXPLAYERS) {
			char className[64];
			GetEntPropString(inflictor, Prop_Data, "m_iClassname", className, sizeof(className));

			if(StrEqual(className, "hegrenade_projectile")) {
				weaponID = view_as<int>(CSWeapon_HEGRENADE);
			} else if(StrEqual(className, "inferno")) {
				weaponID = view_as<int>(CSWeapon_MOLOTOV);
			}
		} 
	} else {
		weaponID = GetWeaponID(weapon);
	}

	csWeaponID = view_as<CSWeaponID>(weaponID);

	if(umiejetnosc[attacker][szansa_z_noza]) {
		if(csWeaponID == CSWeapon_KNIFE && (GetClientButtons(attacker) & IN_ATTACK2) && GetRandomInt(1, umiejetnosc[attacker][szansa_z_noza]) == 1) {
			damage = float(GetClientHealth(client)+1);
			return Plugin_Continue;
		}
	}
	if(umiejetnosc[attacker][szansa_z_broni]) {
		if(szansa_na_zabicie[attacker][CSWeapon_HEGRENADE] && GetRandomInt(1, szansa_na_zabicie[attacker][csWeaponID]) == 1) {
			damage = float(GetClientHealth(client)+1);
		}
		if(szansa_na_zabicie[attacker][csWeaponID] && (damageType & DMG_BULLET) && GetRandomInt(1, szansa_na_zabicie[attacker][csWeaponID]) == 1) {
			damage = float(GetClientHealth(client)+1);
		}
	}
	if(umiejetnosc[attacker][wieksze_obrazenia_z_broni]) {
		if(wieksze_obrazenia[attacker][csWeaponID] && (damageType & DMG_BULLET)) {
			damage *= wieksze_obrazenia[attacker][csWeaponID];
		}
	}
	if(umiejetnosc[attacker][wieksze_obrazenia_z_broni_z_int]) {
		if(wieksze_obrazenia[attacker][csWeaponID] && (damageType & DMG_BULLET)) {
			damage = (damage*wieksze_obrazenia[attacker][csWeaponID])+RoundFloat(cod_get_user_maks_intelligence(attacker)*przelicznik_int[attacker]);
		}
	}

	if(umiejetnosc[attacker][podpalenie]) {
		if((damageType & DMG_BULLET) && GetRandomInt(1, umiejetnosc[attacker][podpalenie]) == 1)
			IgniteEntity(client, 5.0+RoundFloat(cod_get_user_maks_intelligence(attacker)*0.03125));
	}
	
	if(umiejetnosc[attacker][zamrozenie]) {
		if((damageType & DMG_BULLET) && GetRandomInt(1, umiejetnosc[attacker][zamrozenie]) == 1)
			Zamroz(client);
	}

	if(umiejetnosc[attacker][trujace_pociski]) {
		if ((damageType & DMG_BULLET) && GetRandomInt(1, umiejetnosc[attacker][trujace_pociski]) == 1)
			Trucizna(client, attacker, 16, 0.1, 1.0, 0.025);
	}

	if(umiejetnosc[attacker][szybkostrzelnosc]) {
		new active_weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if(!(csWeaponID == CSWeapon_KNIFE)) {
			if(active_weapon != -1) {
				float gametime = GetGameTime();
				float fattack = GetEntDataFloat(active_weapon, FindSendPropInfo("CBaseCombatWeapon", "m_flNextPrimaryAttack"))-gametime;
				SetEntDataFloat(active_weapon, FindSendPropInfo("CBaseCombatWeapon", "m_flNextPrimaryAttack"), (fattack/1.4)+gametime);
			}
		}
	}

	if(umiejetnosc[attacker][oslepienie]) {
		if((damageType & DMG_BULLET) && GetRandomInt(1,umiejetnosc[attacker][oslepienie]) == 1) {
			Fade(client, 750, 300, 0x0001, {255, 255, 255, 255});
		}
	}

	return Plugin_Continue;
}

public Action PlayerBlind(Handle event, const char[] eventName, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));

	if(!IsValidClient(client) || !IsPlayerAlive(client)) {
		return Plugin_Continue;
	}

	SetEntPropFloat(client, Prop_Send, "m_flFlashMaxAlpha", 0.5);
	return Plugin_Continue;
}

public Action SmiercGracza(Handle event, char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int killer = GetClientOfUserId(GetEventInt(event, "attacker"));

	if(!IsValidClient(client) || !IsValidClient(killer) || !IsPlayerAlive(killer) || GetClientTeam(client) == GetClientTeam(killer))
		return Plugin_Continue;

	if(umiejetnosc[client][pelen_magazynek_za_killa]) {
		new active_weapon = GetEntPropEnt(killer, Prop_Send, "m_hActiveWeapon");
		if(active_weapon != -1)
		{
			char weapon[32];
			GetClientWeapon(killer, weapon, sizeof(weapon));
			for(int i = 0; i < sizeof(nazwy_broni); i ++) {
				if(StrEqual(weapon, nazwy_broni[i])) {
					SetEntData(active_weapon, FindSendPropInfo("CWeaponCSBase", "m_iClip1"), naboje_broni[i][0]);
					break;
				}
			}
		}
	}

	if(umiejetnosc[client][hp_za_killa]) {
		int zdrowie_gracza = GetClientHealth(killer);
		int maksymalne_zdrowie = cod_get_user_maks_health(killer);
		int hp = umiejetnosc[client][hp_za_killa];

		SetEntData(killer, FindDataMapInfo(killer, "m_iHealth"), (zdrowie_gracza+hp < maksymalne_zdrowie)? zdrowie_gracza+hp: maksymalne_zdrowie);
	}

	if(umiejetnosc[client][odrodzenie]) {
		if(GetRandomInt(1, umiejetnosc[client][odrodzenie]) == 1)
			CreateTimer(0.1, Wskrzeszenie, client, TIMER_FLAG_NO_MAPCHANGE);
	}

	return Plugin_Continue;
}

public Action NieskonczonyMagazynek(Handle event, char[] name, bool dontbroadcast) {
	new client = GetClientOfUserId(GetEventInt(event, "userid"));
	if(!IsValidClient(client) || !IsPlayerAlive(client))
		return Plugin_Continue;

	if(umiejetnosc[client][nieskonczony_magazynek]){
		new active_weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if(active_weapon != -1)
			SetEntData(active_weapon, FindSendPropInfo("CWeaponCSBase", "m_iClip1"), 5);
	}

	return Plugin_Continue;
}

public Action CicheKroki(clients[64], int &numclients, char sample[PLATFORM_MAX_PATH], int &entity, int &channel, float &volume, int &level, int &pitch, int &flags) {
	if(!IsValidClient(entity) || IsFakeClient(entity))
		return Plugin_Continue;

	if(umiejetnosc[entity][ciche_kroki]) {
		if((StrContains(sample, "physics") != -1 || StrContains(sample, "footsteps") != -1) && StrContains(sample, "suit") == -1)
			return Plugin_Handled;
	} else
		EmitSoundToAll(sample, entity);

	return Plugin_Continue;
}

public void ZdetonowanyDymny(Handle event, const char[] name, bool dontBroadcast) {
	int thrower = GetClientOfUserId(GetEventInt(event, "userid"));

	if(!thrower || !umiejetnosc[thrower][trujace_dymne])
		return;

	int entity = GetEventInt(event, "entityid");
	CreateTimer(0.1, GraczeDoZatrucia, EntIndexToEntRef(entity), TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

public Action GraczeDoZatrucia(Handle timer, any entityRef) {
	int entity = EntRefToEntIndex(entityRef);
	if(entity == INVALID_ENT_REFERENCE)
		return Plugin_Stop;

	float position[2][3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", position[0]);
	int thrower = GetEntDataEnt2(entity, offset_thrower);
	if(!thrower || !IsClientInGame(thrower))
		return Plugin_Stop;

	int team = GetClientTeam(thrower);
	for(int i = 1; i <= MaxClients; i++) {
		if(!IsClientInGame(i) || !IsPlayerAlive(i) || team == GetClientTeam(i)) {
			continue;
		}

		GetClientAbsOrigin(i, position[1]);

		if(GetVectorDistance(position[0], position[1]) <= 220.0) {
			Trucizna(i, thrower, 5, 0.25, 2.0, 0.05);
		}
	}

	return Plugin_Continue;
}

public void Spawn_Post(int client) {
	if (IsPlayerAlive(client)) {
		//Grawitacja
		if(grawitacja_gracza[client])
			SetEntityGravity(client, grawitacja_gracza[client]);

		//Niewidzialność
		int buttons;
		if(umiejetnosc[client][niewidka])
			StartRender(client);
		if(umiejetnosc[client][niewidka_noz]) {
			char weapon[32];
			GetClientWeapon(client, weapon, sizeof(weapon));
			if((StrEqual(weapon, "weapon_bayonet") || StrContains(weapon, "weapon_knife", false) != -1))
				StartRender(client);
			else
				StopRender(client);
		}
		if(umiejetnosc[client][niewidka_kucanie]) {
			if((buttons & IN_DUCK))
				StartRender(client);
			else
				StopRender(client);
		}
		if(umiejetnosc[client][niewidka_kucanie_noz]) {
			if((buttons & IN_DUCK) && GetPlayerWeaponSlot(client, CS_SLOT_KNIFE) == GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon"))
				StartRender(client);
			else
				StopRender(client);
		}

		//Zamrozenie
		if(umiejetnosc[client][zamrozenie]) {
			if(odmrozenie[client] != null) {
				KillTimer(odmrozenie[client]);
				odmrozenie[client] = null;
			}
		}

		if(umiejetnosc[client][trujace_dymne] || umiejetnosc[client][trujace_pociski]) {
			if (zatrucie[client] != null) {
				KillTimer(zatrucie[client]);
				zatrucie[client] = null;
			}
		}

		//Wrogie przebranie
		if(umiejetnosc[client][przebranie]) {
			SetEntityModel(client, (GetClientTeam(client) == CS_TEAM_T)? modele_postaci[GetRandomInt(0, 4)]: modele_postaci[GetRandomInt(5, 9)]);
		} else
			CS_UpdateClientModel(client);
	}
}

public void Think_Post(int client) {
	if(IsPlayerAlive(client)) {
		new weapon = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
		if(!IsValidEdict(weapon) || weapon == -1) {
			return;
		}
		float punchAngle[3];

		if(umiejetnosc[client][brak_rozrzutu_broni]) {
			float multiplier = 0.0;

			SetEntPropFloat(weapon, Prop_Send, "m_fAccuracyPenalty",
			GetEntPropFloat(weapon, Prop_Send, "m_fAccuracyPenalty") * multiplier);

			GetEntPropVector(client, Prop_Send, "m_aimPunchAngle", punchAngle);
			for(int i = 0; i < 3; i++) {
				punchAngle[i] *= multiplier;
			}
			SetEntPropVector(client, Prop_Send, "m_aimPunchAngle", punchAngle);

			GetEntPropVector(client, Prop_Send, "m_aimPunchAngleVel", punchAngle);
			for(int i = 0; i < 3; i++) {
				punchAngle[i] *= multiplier;
			}
			SetEntPropVector(client, Prop_Send, "m_aimPunchAngleVel", punchAngle);

			GetEntPropVector(client, Prop_Send, "m_viewPunchAngle", punchAngle);
			for(int i = 0; i < 3; i++) {
				punchAngle[i] *= multiplier;
			}
			SetEntPropVector(client, Prop_Send, "m_viewPunchAngle", punchAngle);
		}
		if(umiejetnosc[client][mniejszy_rozrzut]) {
			float multiplier = 0.9;

			SetEntPropFloat(weapon, Prop_Send, "m_fAccuracyPenalty",
			GetEntPropFloat(weapon, Prop_Send, "m_fAccuracyPenalty") * multiplier);

			GetEntPropVector(client, Prop_Send, "m_aimPunchAngle", punchAngle);
			for(int i = 0; i < 3; i++) {
				punchAngle[i] *= multiplier;
			}
			SetEntPropVector(client, Prop_Send, "m_aimPunchAngle", punchAngle);

			GetEntPropVector(client, Prop_Send, "m_aimPunchAngleVel", punchAngle);
			for(int i = 0; i < 3; i++) {
				punchAngle[i] *= multiplier;
			}
			SetEntPropVector(client, Prop_Send, "m_aimPunchAngleVel", punchAngle);

			GetEntPropVector(client, Prop_Send, "m_viewPunchAngle", punchAngle);
			for(int i = 0; i < 3; i++) {
				punchAngle[i] *= multiplier;
			}
			SetEntPropVector(client, Prop_Send, "m_viewPunchAngle", punchAngle);
		}
	}
}

void Trucizna(int client, int attacker, int poisons, float time, float damage, float damagePerInt) {
	zatruty[client] = poisons;

	if (zatrucie[client] == null) {
		DataPack dataPack;

		int entity = AttachGlowToPlayer(client, {157, 29, 171, 255});
		if(entity >= 0)
			glowID[client] = EntIndexToEntRef(entity);

		zatrucie[client] = CreateDataTimer(time, czas_zatrucia, dataPack, TIMER_REPEAT);
		WritePackCell(dataPack, attacker);
		WritePackCell(dataPack, client);
		WritePackCell(dataPack, view_as<int>(damage));
		WritePackCell(dataPack, view_as<int>(damagePerInt));
	}
}
public Action czas_zatrucia(Handle hTimer, DataPack dataPack) {
	ResetPack(dataPack);
	int attacker = ReadPackCell(dataPack);
	int client = ReadPackCell(dataPack);
	float damage = view_as<float>(ReadPackCell(dataPack));
	float damagePerInt = view_as<float>(ReadPackCell(dataPack));

	float fDamage = damage+damagePerInt;

	if(!IsClientInGame(client) || !IsPlayerAlive(client) || !IsClientInGame(attacker)) {
		zatrucie[client] = null;
		return Plugin_Stop;
	}

	SDKHooks_TakeDamage(client, attacker, attacker, fDamage, DMG_POISON, -1);

	if(!(--zatruty[client])) {
		RemoveGlow(EntRefToEntIndex(glowID[client]));
		zatrucie[client] = null;
		return Plugin_Stop;
	}
	
	return Plugin_Continue;
}

void Zamroz(int client) {
	if(odmrozenie[client] != null) {
		KillTimer(odmrozenie[client]);
		odmrozenie[client] = null;
	} else {
		int entity = AttachGlowToPlayer(client, {47, 183, 250, 255});

		if(entity >= 0)
			glowID[client] = EntIndexToEntRef(entity);
	}

	float origin[3];

	SetEntityMoveType(client, MOVETYPE_NONE);
	odmrozenie[client] = CreateTimer(4.0, czas_odmrozenie, client, TIMER_FLAG_NO_MAPCHANGE);

	GetClientAbsOrigin(client, origin);
	EmitAmbientSound("physics/glass/glass_strain2.wav", origin, client, SNDLEVEL_RAIDSIREN);
}
public Action czas_odmrozenie(Handle timer, any client) {
	if(IsPlayerAlive(client)) {
		float origin[3];

		SetEntityMoveType(client, MOVETYPE_WALK);
		RemoveGlow(EntRefToEntIndex(glowID[client]));

		GetClientAbsOrigin(client, origin);
		EmitAmbientSound("physics/glass/glass_bottle_break2.wav", origin, client, SNDLEVEL_RAIDSIREN);
	}

	odmrozenie[client] = null;
}
int AttachGlowToPlayer(int client, const int iColors[4]) {
	int iEnt = CreateEntityByName("prop_dynamic_glow");
	if(iEnt == -1)
		return -1;

	char szModel[256];

	GetClientModel(client, szModel, sizeof(szModel));

	DispatchKeyValue(iEnt, "model", szModel);
	DispatchKeyValue(iEnt, "solid", "0");
	DispatchKeyValue(iEnt, "fademindist", "1");
	DispatchKeyValue(iEnt, "fademaxdist", "1");
	DispatchKeyValue(iEnt, "fadescale", "2.0");
	SetEntProp(iEnt, Prop_Send, "m_CollisionGroup", 0);
	DispatchSpawn(iEnt);
	SetEntityRenderMode(iEnt, RENDER_GLOW);
	SetEntityRenderColor(iEnt, 0, 0, 0, 0);
	SetEntProp(iEnt, Prop_Send, "m_fEffects", EF_BONEMERGE);
	SetVariantString("!activator");
	AcceptEntityInput(iEnt, "SetParent", client, iEnt);
	SetVariantString("primary");
	AcceptEntityInput(iEnt, "SetParentAttachment", iEnt, iEnt, 0);
	SetVariantString("OnUser1 !self:Kill::0.1:-1");
	AcceptEntityInput(iEnt, "AddOutput");

	static int iOffset;

	if (!iOffset && (iOffset = GetEntSendPropOffs(iEnt, "m_clrGlow")) == -1) {
		AcceptEntityInput(iEnt, "FireUser1");
		LogError("Unable to find property offset: \"m_clrGlow\"!");
		return -1;
	}

	// Enable glow for custom skin
	SetEntProp(iEnt, Prop_Send, "m_bShouldGlow", true);
	SetEntProp(iEnt, Prop_Send, "m_nGlowStyle", 1);
	SetEntPropFloat(iEnt, Prop_Send, "m_flGlowMaxDist", 10000.0);

	// So now setup given glow colors for the skin
	for(int i=0;i<3;i++) {
		SetEntData(iEnt, iOffset + i, iColors[i], _, true); 
	}

	return iEnt;
}
void RemoveGlow(int iEnt) {
	if(iEnt != INVALID_ENT_REFERENCE) {
		SetEntProp(iEnt, Prop_Send, "m_bShouldGlow", false);
		AcceptEntityInput(iEnt, "FireUser1");
	}
}

public Action Wskrzeszenie(Handle timer, any client) {
	if(!IsValidClient(client))
		return Plugin_Continue;

	CS_RespawnPlayer(client);
	return Plugin_Continue;
}

void Fade(client, duration, hold_time, flags, const colors[4]) {
	Handle message = StartMessageOne("Fade", client, 1);

	PbSetInt(message, "duration", duration);
	PbSetInt(message, "hold_time", hold_time);
	PbSetInt(message, "flags", flags);
	PbSetColor(message, "clr", colors);

	EndMessage();
}

int UstawSkill(int client, int parametr, int wartosc) {
	if(IsClientInGame(client)) {
		if(parametr == 0) {
			WyzerujSkill(client)
			return 0;
		}
		umiejetnosc[client][parametr] = wartosc;
	}

	return 0;
}
void WyzerujSkill(client) {
	for(int i=1;i<MAX_SKILLI;i++) {
		if(IsClientInGame(client))
			umiejetnosc[client][i] = 0;
	}
}

int UstawGrawitacje(int client, float wartosc) {
	if(IsClientInGame(client)) {
		grawitacja_gracza[client] = wartosc;

		if(GetEntityGravity(client) != grawitacja_gracza[client])
			SetEntityGravity(client, grawitacja_gracza[client]);
	}

	return 0;
}

int UstawZabojstwa(int client, int bron, int wartosc) {
	if(IsClientInGame(client)) {	
		if(bron == 0) {
			WyzerujZabojstwa(client);
			return 0;
		}
		szansa_na_zabicie[client][bron] = wartosc;
		umiejetnosc[client][szansa_z_broni] = 1;
	}
	return 0;
}
void WyzerujZabojstwa(client) {
	for(int i=1;i<32;i++) {
		if(IsClientInGame(client))
			szansa_na_zabicie[client][i] = 0;
	}
}

int UstawObrazenia(int client, int bron, float obrazenia) {
	if(IsClientInGame(client)) {	
		if(bron == 0) {
			WyzerujObrazenia(client);
			return 0;
		}
		wieksze_obrazenia[client][bron] = obrazenia;
		umiejetnosc[client][wieksze_obrazenia_z_broni] = 1;
	}
	return 0;
}
void WyzerujObrazenia(client) {
	for(int i=1;i<32;i++) {
		if(IsClientInGame(client))
			wieksze_obrazenia[client][i] = 0.0;
	}
}
int UstawObrazeniaZInt(int client, int bron, float obrazenia, float przelicznik) {
	if(IsClientInGame(client)) {	
		if(bron == 0) {
			WyzerujObrazeniaZInt(client);
			return 0;
		}
		wieksze_obrazenia[client][bron] = obrazenia;
		przelicznik_int[client] = przelicznik;
		umiejetnosc[client][wieksze_obrazenia_z_broni_z_int] = 1;
	}
	return 0;
}
void WyzerujObrazeniaZInt(client) {
	for(int i=1;i<32;i++) {
		if(IsClientInGame(client)) {
			wieksze_obrazenia[client][i] = 0.0;
			przelicznik_int[client] = 0.0;
		}
	}
}

int GetWeaponID(int weapon) {
	CSWeaponID weaponId;

	weaponId = CS_ItemDefIndexToID(GetEntProp(weapon, Prop_Send, "m_iItemDefinitionIndex"));

	if(_:weaponId < 0) {
		return 0;
	} else if(_:weaponId > MAX_WEAPONS || weaponId == CSWeapon_KNIFE_GG || weaponId == CSWeapon_KNIFE_T || weaponId == CSWeapon_KNIFE_GHOST) {
		return _:CSWeapon_KNIFE;
	}

	return _:weaponId;
}

void StartRender(int client) {
	vis = umiejetnosc[client][niewidka];

	if(umiejetnosc[client][niewidka_noz]) {
		vis = umiejetnosc[client][niewidka_noz];
	}
	if(umiejetnosc[client][niewidka_kucanie]) {
		vis = umiejetnosc[client][niewidka_kucanie];
	}
	if(umiejetnosc[client][niewidka_kucanie_noz]) {
		vis = umiejetnosc[client][niewidka_kucanie_noz];
	}

	if(vis < 255) {
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client, 255, 255, 255, vis);
	} else
		StopRender(client);
}
void StopRender(int client) {
	SetEntityRenderMode(client, RENDER_NORMAL);
}