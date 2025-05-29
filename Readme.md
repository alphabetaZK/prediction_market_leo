## Leo market prediction testing branch



# Constantes

| Nom                               | Type      | Sens                                                              |
| --------------------------------- | --------- | ----------------------------------------------------------------- |
| `CREATION_FEE`, `MIN_BET`         | `u64`     | Montants minimums exprimés en micro-credits ( 10-6  ALEO).        |
| `MAX_OPTIONS`, `MAX_OPEN_MARKETS` | `u8`      | Limites de complexité pour garder les preuves petites.            |
| `SECONDS_PER_DAY`                 | `u32`     | Conversion pratique pour la durée d’un marché.                    |
| `STATUS_*`                        | `u8`      | Enum “fait maison” : 0 =open, 1 =closed, 2 =canceled, 3 =invalid. |
| `ADMIN`                           | `address` | Autorité qui perçoit les frais et peut clôturer/annuler.          |

# Types métier

| Mot-clé   | Particularité Leo                                                                                                                     |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| `struct`  | Stocké **en clair** on-chain. Ici : `Market`.                                                                                         |
| `record`  | Objet **chiffré & privé** tenu par l’utilisateur : <br>• `BetRecord` = ticket de pari <br>• `MarketReceipt`, `RewardReceipt` = reçus. |
| `mapping` | Table clé → valeur gérée par la chaîne ; lecture/écriture via `Mapping::*`.                                                           |

# Cycle de vie d’un marché

1. **`create_market` (transition)**

   * Le client paie `CREATION_FEE` et publie la preuve.
   * En `finalize`, le smart-contract :

     1. crée l’entrée `Market` et l’ajoute à la liste des marchés ouverts ;
     2. crédite les frais sur `admin_fees[ADMIN]`.

2. **`place_bet`**

   * Le ticket (`BetRecord`) est produit côté client.
   * `place_bet_finalize` incrémente le *pool* choisi et la *total\_pool*.

3. **`close_market_with_winner`** (réservé admin)

   * Vérifie que la date limite est passée.
   * Fige l’état : `status = CLOSED`, `winning_option = x`.

4. **Réclamations**

   * `claim_winnings`
     *•* Le ticket est marqué comme **réclamé** dans `claimed_bets`.
     *•* Le contrat ne calcule pas la part : le client donne la valeur et prouve qu’elle est correcte dans la preuve (division complexe évitée on-chain).
   * `claim_refund` (marché annulé) : rembourse la mise.

5. **Maintenance & lecture**

   * `withdraw_admin_fees` : l’admin vide sa cagnotte.
   * `list_open_markets` : expose jusqu’à 100 IDs actifs (UX côté front).