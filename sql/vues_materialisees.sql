-- Ici pour nos vues c'est assez simple, on prends nos requêtes telles qu'elles sont et on rajoute de quoi créer
-- une vue au début de celle-ci, ainsi nos résultats seront directement accesibles sur ces vues, ça évite de faire
-- des requêtes lourdes par dessus des requêtes déja lourdes, par contre ça peut devenir enmbêtant en terme de stockage
-- parce que ça fait beaucoup de lignes à un moment. Pour le moment on pourrait avoir ça : 

-- V1 : flux d'abonnés par mois, région et ancienneté (sert R1 et R2)
CREATE MATERIALIZED VIEW mv_flux_region
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
-- ENABLE QUERY REWRITE -- (potentiellement pas les drois)
AS
SELECT d.annee,
       d.mois,
       f.type_evenement_sk,
       g.region,
       CASE WHEN f.anciennete_mois < 3  THEN '0-2 mois'
            WHEN f.anciennete_mois < 12 THEN '3-11 mois'
            WHEN f.anciennete_mois < 24 THEN '12-23 mois'
            ELSE '24 mois et +' END AS tranche_anciennete,
       COUNT(*)             AS nb_evenements,
       SUM(f.delta_abonnes) AS solde
FROM fait_evenement_abonnement f
JOIN dim_date       d ON f.date_evenement_sk = d.date_sk
JOIN dim_geographie g ON f.geo_sk = g.geo_sk
GROUP BY d.annee, d.mois, f.type_evenement_sk, g.region,
         CASE WHEN f.anciennete_mois < 3  THEN '0-2 mois'
              WHEN f.anciennete_mois < 12 THEN '3-11 mois'
              WHEN f.anciennete_mois < 24 THEN '12-23 mois'
              ELSE '24 mois et +' END;

-- V2 : activité commerciale par offre, canal et promotion (sert R3, R4 et R5)
CREATE MATERIALIZED VIEW mv_commercial
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
-- ENABLE QUERY REWRITE -- (potentiellement pas les drois)
AS
SELECT d.annee,
       d.mois,
       f.type_evenement_sk,
       f.offre_sk,
       f.canal_sk,
       f.promotion_sk,
       COUNT(*)                 AS nb_evenements,
       SUM(f.anciennete_mois)   AS somme_anciennete,
       COUNT(f.anciennete_mois) AS nb_anciennete,
       SUM(f.montant_remise)    AS somme_remises,
       SUM(f.montant_ttc)       AS somme_ttc
FROM fait_evenement_abonnement f
JOIN dim_date d ON f.date_evenement_sk = d.date_sk
GROUP BY d.annee, d.mois, f.type_evenement_sk, f.offre_sk, f.canal_sk, f.promotion_sk;


-- Bon ici, je vais pas m'embêter à recréer toutes les requêtes à la main comme en partie 2, l'IA me les fait sur les vues : 


-- R1 sur V1
SELECT v.mois, t.type_evenement,
       SUM(v.nb_evenements) AS nb_evenements,
       SUM(v.solde)         AS solde_net
FROM mv_flux_region v
JOIN dim_type_evenement t ON v.type_evenement_sk = t.type_evenement_sk
WHERE v.annee = 2026
GROUP BY ROLLUP (v.mois, t.type_evenement)
ORDER BY v.mois, t.type_evenement;

-- R2 sur V1 : le CASE est déjà calculé dans la vue
WITH actifs AS (
  SELECT region, SUM(solde) AS actifs_debut
  FROM mv_flux_region
  WHERE annee < 2026
  GROUP BY region
),
resiliations AS (
  SELECT v.region, v.tranche_anciennete, SUM(v.nb_evenements) AS nb_resiliations
  FROM mv_flux_region v
  JOIN dim_type_evenement t ON v.type_evenement_sk = t.type_evenement_sk
  WHERE t.sens = 'Sortie' AND v.annee = 2026
  GROUP BY v.region, v.tranche_anciennete
)
SELECT r.region, r.tranche_anciennete, r.nb_resiliations, a.actifs_debut,
       ROUND(100 * r.nb_resiliations / NULLIF(a.actifs_debut, 0), 2) AS taux_pct
FROM resiliations r
LEFT JOIN actifs a ON r.region = a.region
ORDER BY taux_pct DESC NULLS LAST;

-- R3 sur V2 : la moyenne est recalculée à partir de la somme et du nombre
SELECT o.libelle_offre, t.initiateur, t.motif_resiliation,
       SUM(v.nb_evenements)                         AS nb_resiliations,
       SUM(v.somme_anciennete) / SUM(v.nb_anciennete) AS anciennete_moyenne_mois
FROM mv_commercial v
JOIN dim_type_evenement t ON v.type_evenement_sk = t.type_evenement_sk
JOIN dim_offre          o ON v.offre_sk = o.offre_sk
WHERE t.type_evenement = 'Résiliation' AND v.annee = 2026
GROUP BY o.libelle_offre, t.initiateur, t.motif_resiliation
ORDER BY o.libelle_offre, nb_resiliations DESC;

-- R4 sur V2
SELECT c.famille AS canal, o.libelle_offre AS offre,
       SUM(v.nb_evenements) AS nb_souscriptions
FROM mv_commercial v
JOIN dim_canal          c ON v.canal_sk = c.canal_sk
JOIN dim_offre          o ON v.offre_sk = o.offre_sk
JOIN dim_type_evenement t ON v.type_evenement_sk = t.type_evenement_sk
WHERE t.type_evenement = 'Souscription' AND v.annee = 2026
GROUP BY CUBE (c.famille, o.libelle_offre)
ORDER BY c.famille, o.libelle_offre;

-- R5 sur V2 : pour une souscription, le mois de l'événement est la cohorte
SELECT p.libelle_promo,
       v.annee || '-' || LPAD(v.mois, 2, '0')        AS cohorte,
       SUM(v.nb_evenements)                          AS nb_nouveaux_abonnes,
       SUM(v.somme_remises)                          AS cout_total_remises,
       SUM(v.somme_remises) / SUM(v.nb_evenements)   AS cout_par_abonne
FROM mv_commercial v
JOIN dim_promotion      p ON v.promotion_sk = p.promotion_sk
JOIN dim_type_evenement t ON v.type_evenement_sk = t.type_evenement_sk
WHERE t.type_evenement = 'Souscription'
GROUP BY p.libelle_promo, v.annee, v.mois
ORDER BY v.annee, v.mois, nb_nouveaux_abonnes DESC;