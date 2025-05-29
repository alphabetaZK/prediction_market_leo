## Testme.md Documentation Leo

Types `u32`/`bool` ne correspondent pas au contrat (qui attend `field`, `u64`, etc.) -> Types alignés sur la signature réelle

Chaque transition du test doit *créer* ses arguments privés (ticket, etc.) ou les recevoir en paramètre -> Ajout d’un constructeur inline ou d’un paramètre
