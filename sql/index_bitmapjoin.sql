-- Les requêtes R3 et R4 sont un bon modèle de jointure : en effet, les deux effectuent une selection sur des attributs
-- de même dimension. type_evenement n'a que 5 valeurs possibles , et annee une dizaine. On fait un filtre sur
-- DIM_TYPE_EVENEMENT et DIM_DATE ducoup car un seul index sur ces deux colonnes optimise les 2 requêtes.

-- Fait à partir du modèle README.md du git BDD, on commence par le nettoyage et la création de l'index

SET SQLBLANKLINES ON

-- Nettoyage si le script a déjà été lancé
BEGIN
    EXECUTE IMMEDIATE 'DROP INDEX idx_bj_type_annee';
EXCEPTION
    WHEN OTHERS THEN NULL;
END;
/

-- Index bitmap de jointure sur deux dimensions :
-- le type d'événement (DIM_TYPE_EVENEMENT) et l'année de l'événement (DIM_DATE)
CREATE BITMAP INDEX idx_bj_type_annee
ON fait_evenement_abonnement (t.type_evenement, d.annee)
FROM fait_evenement_abonnement f, dim_type_evenement t, dim_date d
WHERE f.type_evenement_sk = t.type_evenement_sk
  AND f.date_evenement_sk = d.date_sk;

-- Ok génial, notre index est là, maintenant on aimerai bien générer en masse des infos pour que l'index
-- soit utile. J'ai demandé à l'IA de me faire une boucle de 20000 évènements de test, fictifs, avec une répartition
-- réaliste. Donc on a 90% de renouvellement, 5% de souscriptions et 5% de résiliations.

-- Génération de 20 000 événements de test (num_contrat commence par GEN-)
BEGIN
    FOR i IN 1..20000 LOOP
        INSERT INTO fait_evenement_abonnement
          (date_evenement_sk, date_souscription_sk, heure_sk, lecteur_sk, offre_sk,
           promotion_sk, geo_sk, canal_sk, type_evenement_sk,
           num_contrat, num_transaction,
           montant_ttc, montant_ht, montant_remise, nb_mois_factures,
           delta_abonnes, revenu_cumule_abonne, anciennete_mois, taux_remise)
        VALUES (
          CASE MOD(i, 4) WHEN 0 THEN 20240110 WHEN 1 THEN 20260110
                         WHEN 2 THEN 20260115 ELSE 20260215 END,
          20240110,
          CASE MOD(i, 3) WHEN 0 THEN 5 WHEN 1 THEN 1240 ELSE 2130 END,
          CASE MOD(i, 2) WHEN 0 THEN 1001 ELSE 1002 END,
          CASE MOD(i, 2) WHEN 0 THEN 12 ELSE 20 END,
          0,
          CASE MOD(i, 2) WHEN 0 THEN 690 ELSE 350 END,
          CASE MOD(i, 3) WHEN 0 THEN 8 ELSE 5 END,
          CASE WHEN MOD(i, 20) = 0 THEN 3
               WHEN MOD(i, 20) = 1 THEN 1
               ELSE 2 END,
          'GEN-' || i, NULL,
          11.99, 11.74, 0, 1,
          CASE WHEN MOD(i, 20) = 0 THEN -1
               WHEN MOD(i, 20) = 1 THEN 1
               ELSE 0 END,
          11.99, MOD(i, 36), 0
        );
    END LOOP;
    COMMIT;
END;
/

-- Statistiques à jour pour que l'optimiseur connaisse le nouveau volume
EXEC DBMS_STATS.GATHER_TABLE_STATS(USER, 'FAIT_EVENEMENT_ABONNEMENT');

-- Ok, jusque là on est bon, on a nos infos, notre index bitmap, mais concrètement c'est quoi le plan d'exécution de
-- nos 2 requêtes avec l'index (on pourrait faire avec et sans le bitmap pour comparer bien sûr). On va juste faire
-- un EXPLAIN PLAN sur la requête qu'on a déja faite avant donc rien d'intéressant à expliquer, on est dans l'analyse ici

EXPLAIN PLAN FOR
SELECT /*+ INDEX(f idx_bj_type_annee) */
       o.libelle_offre, t.initiateur, t.motif_resiliation,
       COUNT(*) AS nb_resiliations,
       AVG(f.anciennete_mois) AS anciennete_moyenne_mois
FROM fait_evenement_abonnement f
JOIN dim_type_evenement t ON f.type_evenement_sk = t.type_evenement_sk
JOIN dim_offre o ON f.offre_sk = o.offre_sk
JOIN v_date_evenement de ON f.date_evenement_sk = de.date_evenement_sk
WHERE t.type_evenement = 'Résiliation'
  AND de.annee_evenement = 2026
GROUP BY o.libelle_offre, t.initiateur, t.motif_resiliation;

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY); -- Affichage du plan

EXPLAIN PLAN FOR
SELECT /*+ INDEX(f idx_bj_type_annee) */
       c.famille AS canal, o.libelle_offre AS offre,
       COUNT(*) AS nb_souscriptions
FROM fait_evenement_abonnement f
JOIN dim_canal c ON f.canal_sk = c.canal_sk
JOIN dim_offre o ON f.offre_sk = o.offre_sk
JOIN dim_type_evenement t ON f.type_evenement_sk = t.type_evenement_sk
JOIN v_date_evenement de ON f.date_evenement_sk = de.date_evenement_sk
WHERE t.type_evenement = 'Souscription'
  AND de.annee_evenement = 2026
GROUP BY CUBE (c.famille, o.libelle_offre);

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY); -- Pareil, on affiche on dessus

-- Petite requête qui n'utilise justement pas l'index : 

EXPLAIN PLAN FOR
SELECT COUNT(*)
FROM fait_evenement_abonnement f
JOIN dim_type_evenement t ON f.type_evenement_sk = t.type_evenement_sk
WHERE t.sens = 'Sortie';

SELECT * FROM TABLE(DBMS_XPLAN.DISPLAY);

-- Nettoyage des données générales : 

DELETE FROM fait_evenement_abonnement WHERE num_contrat LIKE 'GEN-%';
COMMIT;