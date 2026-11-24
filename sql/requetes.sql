-- Quelques requêtes sur le modèle principal


-- Requête 1 : Dans modele_detaille.sql, on a une requête déja pour le solde net par mois et les évènements. Petite
-- précision ici : un solde négatif signifie que les départs l'emportent sur les arrivées.


-- Requête 2 : Taux de désabonnement par région et par ancienneté : assez complexe, il faut la regarder étape par
-- étape pour bien la cerner. L'important est d'abord de faire un petit tri au départ avec le WITH actifs et résiliations
-- qui permettent d'avoir une généralité sur les abonnés actifs du 01/01/2026, par région et des résiliations 2026, par
-- région ET ancienneté.


WITH actifs AS(
    SELECT g.region, SUM(f.delta_abonnes) AS actifs_debut -- On récupère ce qui nous intéresse
    FROM fait_evenement_abonnement f -- La table de faits
    JOIN v_date_evenement de ON f.date_evenement_sk = de.date_evenement_sk -- JOIN entre la vue et la TDF
    JOIN dim_geographie g ON f.geo_sk = g.geo_sk -- JOIN pour la dimension qui nous donne la région
    WHERE de.date_evenement < DATE '2026-01-01'
    GROUP BY g.region
), -- On a nos actifs, superbe, on passe à nos désabonnements
resiliations AS (
    SELECT g.region, -- On prends la région, mais j'ai trouvé intéressant de poser le fait que ce soit 
            CASE WHEN f.anciennete_mois < 3 THEN '0-2 mois' -- entre 0-2 mois ou alors 3-11 mois, 12-23 mois ou
                WHEN f.anciennete_mois < 12 THEN '3-11 mois'   -- plus de 24 mois pour savoir la tranche d'ancienneté
                WHEN f.anciennete_mois < 24 THEN '12-23 mois' -- DES DESABONNEMENTS (c'est pas l'âge c'est les désabonnements)
                ELSE '24 mois et +' END AS tranche_anciennete,
            COUNT(*) AS nb_resiliations
    FROM fait_evenement_abonnement f
    JOIN v_date_evenement de ON f.date_evenement_sk = de.date_evenement_sk
    JOIN dim_type_evenement t ON f.type_evenement_sk = t.type_evenement_sk
    JOIN dim_geographie g ON f.geo_sk = g.geo_sk
    WHERE t.sens = 'Sortie' AND de.annee_evenement = 2026 -- Rappel, t.sens c'est si on a une nouvelle entrée, un maintien ou une sortie
    GROUP BY g.region, -- On GROUP BY par ce qu'on a créé pour la lisibilité (ctrl c + ctrl v ici)
        CASE WHEN f.anciennete_mois < 3  THEN '0-2 mois'
                WHEN f.anciennete_mois < 12 THEN '3-11 mois'
                WHEN f.anciennete_mois < 24 THEN '12-23 mois'
                ELSE '24 mois et +' END
)
-- Nous manque plus que SELECT là-dessus (correction par l'IA car je m'étais trompé sur le ROUND pour le dénominateur)
SELECT r.region, r.tranche_anciennete, r.nb_resiliations, a.actifs_debut,
    ROUND(100 * r.nb_resiliations / NULLIF(a.actifs_debut, 0), 2) AS taux_pct -- taux désabo en %
    FROM resiliations r
    LEFT JOIN actifs a ON r.region = a.region -- LEFT JOIN parce qu'on veut toutes les lignes des résiliations, même si y a rien
    -- Suggérée par IA, on classe le taux_pct par ordre décroissant avec NULL à la fin :)
    ORDER BY taux_pct DESC NULLS LAST;


-- Requête 3 : Faisons plus simple cette fois-ci, pour chaque offre, combien d’abonnés sont partis en 2026, 
-- qui a déclenché le départ (l’abonné ou le système), pour quel motif, et après combien de mois en moyenne.


SELECT o.libelle_offre, t.initiateur, t.motif_resiliation, COUNT(*) AS nb_resiliations, AVG(f.anciennete_mois) AS anciennete_moyenne_mois
FROM fait_evenement_abonnement f
JOIN dim_type_evenement t ON f.type_evenement_sk = t.type_evenement_sk
JOIN dim_offre o ON f.offre_sk = o.offre_sk
JOIN v_date_evenement de ON f.date_evenement_sk = de.date_evenement_sk
WHERE t.type_evenement = 'Résiliation'
    AND de.annee_evenement = 2026
GROUP BY o.libelle_offre, t.initiateur, t.motif_resiliation
ORDER BY o.libelle_offre, nb_resiliations DESC;


-- Requête 4 : Testons avec un CUBE quels canaux recrutent des abonnés, et sur quelles offres ?


SELECT c.famille AS canal, o.libelle_offre AS offre, COUNT(*) AS nb_souscriptions -- Assez clair
FROM fait_evenement_abonnement f
JOIN dim_canal c  ON f.canal_sk = c.canal_sk
JOIN dim_offre o  ON f.offre_sk = o.offre_sk
JOIN dim_type_evenement t ON f.type_evenement_sk = t.type_evenement_sk
JOIN v_date_evenement de ON f.date_evenement_sk = de.date_evenement_sk
WHERE t.type_evenement = 'Souscription'
  AND de.annee_evenement = 2026
GROUP BY CUBE (c.famille, o.libelle_offre)
ORDER BY c.famille, o.libelle_offre;
-- Un GROUP BY classique donnerait seulement le détail canal × offre. CUBE calcule en plus tous les sous-totaux
-- possibles, en une seule requête. Une case vide (NULL) veut dire « tous », on peut en tirer quel canal recrute
-- le plus, quelle offre se vend le mieux et les lignes en détail. 


-- Requête 5 : Ici, j'ai demandé à l'IA une requête claire : ombien chaque promotion a-t-elle recruté d’abonnés, 
-- et combien a-t-elle coûté au journal ?


SELECT p.libelle_promo,
       ds.cohorte,
       COUNT(*)                          AS nb_nouveaux_abonnes,
       SUM(f.montant_remise)             AS cout_total_remises,
       SUM(f.montant_remise) / COUNT(*)  AS cout_par_abonne
FROM fait_evenement_abonnement f
JOIN dim_promotion       p  ON f.promotion_sk = p.promotion_sk
JOIN v_date_souscription ds ON f.date_souscription_sk = ds.date_souscription_sk
JOIN dim_type_evenement  t  ON f.type_evenement_sk = t.type_evenement_sk
WHERE t.type_evenement = 'Souscription'
GROUP BY p.libelle_promo, ds.cohorte
ORDER BY ds.cohorte, nb_nouveaux_abonnes DESC;