#if defined _codmod_umiejetnosci_included
  #endinput
#endif
#define _codmod_umiejetnosci_included

#include <cstrike>

#define EF_BONEMERGE				(1 << 0)
#define EF_NOSHADOW				 	(1 << 4)
#define EF_NORECEIVESHADOW		  	(1 << 6)

#define MAX_SKILLI 23
enum {
	zeruj=0,
	autobh, ciche_kroki,
	odrodzenie, przebranie,
	dlugi_skok, multi_skok,
	brak_rozrzutu_broni, mniejszy_rozrzut,
	niewidka, niewidka_noz, niewidka_kucanie, niewidka_kucanie_noz,
	szansa_z_broni, hp_za_killa, pelen_magazynek_za_killa, szansa_z_noza,
	wieksze_obrazenia_z_broni, wieksze_obrazenia_z_broni_z_int,
	podpalenie, zamrozenie, trujace_dymne, trujace_pociski
}

native cod_set_skill(client, parametr, wartosc);
native cod_set_gravity(client, float wartosc);
native cod_set_weapon_chance(client, CSWeaponID bron, wartosc);
native cod_set_more_damage(client, CSWeaponID bron, float obrazenia);
native cod_set_more_damage_int(client, CSWeaponID bron, float obrazenia, float przelicznik);