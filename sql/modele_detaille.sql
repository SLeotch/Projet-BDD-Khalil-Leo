BEGIN
    FOR t IN(SELECT table_name FROM user_tables
        WHERE table_name IN ('FAIT_EVENEMENT_ABONNEMENT', 'DIM_DATE',
                                 'DIM_HEURE', 'DIM_LECTEUR', 'DIM_OFFRE',
                                 'DIM_PROMOTION', 'DIM_GEOGRAPHIE',
                                 'DIM_CANAL', 'DIM_TYPE_EVENEMENT'))
    LOOP
        EXECUTE IMMEDIATE 'DROP TABLE' || t.table_name || 'CASCADE CONSTRAINTS PURGE';
    END LOOP;
END;
/

-- ============================================================
--  1. Dimensions (fait par IA avec le modèle)
-- ============================================================

CREATE TABLE dim_date (
  date_sk              NUMBER(8)     PRIMARY KEY,   -- format AAAAMMJJ
  date_complete        DATE          NOT NULL,
  jour_semaine         VARCHAR2(10)  NOT NULL,
  est_weekend          VARCHAR2(3)   CHECK (est_weekend IN ('Oui','Non')),
  semaine_iso          VARCHAR2(8),
  mois                 NUMBER(2)     NOT NULL,
  libelle_mois         VARCHAR2(10)  NOT NULL,
  trimestre            NUMBER(1)     NOT NULL,
  semestre             NUMBER(1)     NOT NULL,
  annee                NUMBER(4)     NOT NULL,
  est_jour_ferie       VARCHAR2(3)   CHECK (est_jour_ferie IN ('Oui','Non')),
  periode_commerciale  VARCHAR2(40)
);

CREATE TABLE dim_heure (
  heure_sk                NUMBER(4)    PRIMARY KEY,  -- format HHMM
  heure_num               NUMBER(2)    NOT NULL CHECK (heure_num BETWEEN 0 AND 23),
  minute_num              NUMBER(2)    NOT NULL CHECK (minute_num BETWEEN 0 AND 59),
  tranche_horaire         VARCHAR2(10) NOT NULL,
  est_heure_de_pointe     VARCHAR2(3)  CHECK (est_heure_de_pointe IN ('Oui','Non')),
  apres_envoi_newsletter  VARCHAR2(3)  CHECK (apres_envoi_newsletter IN ('Oui','Non'))
);

CREATE TABLE dim_lecteur (
  lecteur_sk            NUMBER(10)    PRIMARY KEY,
  id_compte_source      VARCHAR2(20)  NOT NULL,
  tranche_age           VARCHAR2(15),
  categorie_socio_pro   VARCHAR2(40),
  est_etudiant          VARCHAR2(3)   CHECK (est_etudiant IN ('Oui','Non')),
  temps_visite_jour     VARCHAR2(20),               -- en tranches
  temps_visite_semaine  VARCHAR2(20),               -- en tranches
  rubriques_preferees   VARCHAR2(100),
  date_creation_compte  DATE,
  debut_validite        DATE          NOT NULL,     -- SCD type 2
  fin_validite          DATE          NOT NULL      -- 9999-12-31 = version courante
);

CREATE TABLE dim_offre (
  offre_sk               NUMBER(5)     PRIMARY KEY,
  code_offre             VARCHAR2(20)  NOT NULL,
  libelle_offre          VARCHAR2(60)  NOT NULL,
  est_premium            VARCHAR2(3)   CHECK (est_premium IN ('Oui','Non')),
  support                VARCHAR2(30),
  periodicite            VARCHAR2(15),
  prix_catalogue_ttc     NUMBER(7,2)   NOT NULL,
  duree_engagement_mois  NUMBER(3)     DEFAULT 0,
  inclusions             VARCHAR2(100),
  date_lancement         DATE,
  est_active             VARCHAR2(3)   CHECK (est_active IN ('Oui','Non'))
);

CREATE TABLE dim_promotion (
  promotion_sk      NUMBER(6)     PRIMARY KEY,      -- 0 = aucune promotion
  code_promo        VARCHAR2(20),
  libelle_promo     VARCHAR2(60)  NOT NULL,
  type_remise       VARCHAR2(20),
  valeur_remise     NUMBER(7,2),
  duree_promo_mois  NUMBER(3),
  prix_promo_ttc    NUMBER(7,2),
  public_cible      VARCHAR2(30),
  date_debut        DATE,
  date_fin          DATE,
  evenement         VARCHAR2(40)
);

CREATE TABLE dim_geographie (
  geo_sk        NUMBER(8)     PRIMARY KEY,
  pays          VARCHAR2(40)  NOT NULL,
  zone_geo      VARCHAR2(40),
  region        VARCHAR2(60),
  departement   VARCHAR2(60),
  ville         VARCHAR2(60),
  commune       VARCHAR2(60),
  code_postal   VARCHAR2(10),
  code_insee    VARCHAR2(10)
);

CREATE TABLE dim_canal (
  canal_sk              NUMBER(5)     PRIMARY KEY,
  libelle_canal         VARCHAR2(60)  NOT NULL,
  famille               VARCHAR2(30),
  plateforme            VARCHAR2(20),
  type_appareil         VARCHAR2(20),
  est_payant            VARCHAR2(3)   CHECK (est_payant IN ('Oui','Non')),
  source_utm            VARCHAR2(50),
  medium_utm            VARCHAR2(30),
  nom_campagne          VARCHAR2(60),
  partenaire            VARCHAR2(60),
  cout_unitaire_estime  NUMBER(7,2)
);

CREATE TABLE dim_type_evenement (
  type_evenement_sk         NUMBER(5)     PRIMARY KEY,
  type_evenement            VARCHAR2(30)  NOT NULL,
  sens                      VARCHAR2(10)  NOT NULL
                            CHECK (sens IN ('Entrée','Maintien','Sortie')),
  motif_resiliation         VARCHAR2(40),
  initiateur                VARCHAR2(20),
  moyen_paiement            VARCHAR2(20),
  statut_paiement           VARCHAR2(20),
  offre_retention_proposee  VARCHAR2(3)   CHECK (offre_retention_proposee IN ('Oui','Non')),
  offre_retention_acceptee  VARCHAR2(3)   CHECK (offre_retention_acceptee IN ('Oui','Non'))
);

-- ============================================================
--  2. Table des faits
-- ============================================================

CREATE TABLE fait_evenement_abonnement (
  evenement_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,

  -- Clés étrangères (DIM_DATE est utilisée deux fois : 2 rôles)
  date_evenement_sk     NUMBER(8)  NOT NULL REFERENCES dim_date(date_sk),
  date_souscription_sk  NUMBER(8)  NOT NULL REFERENCES dim_date(date_sk),
  heure_sk              NUMBER(4)  NOT NULL REFERENCES dim_heure(heure_sk),
  lecteur_sk            NUMBER(10) NOT NULL REFERENCES dim_lecteur(lecteur_sk),
  offre_sk              NUMBER(5)  NOT NULL REFERENCES dim_offre(offre_sk),
  promotion_sk          NUMBER(6)  NOT NULL REFERENCES dim_promotion(promotion_sk),
  geo_sk                NUMBER(8)  NOT NULL REFERENCES dim_geographie(geo_sk),
  canal_sk              NUMBER(5)  NOT NULL REFERENCES dim_canal(canal_sk),
  type_evenement_sk     NUMBER(5)  NOT NULL REFERENCES dim_type_evenement(type_evenement_sk),

  -- Dimensions dégénérées
  num_contrat           VARCHAR2(20) NOT NULL,
  num_transaction       VARCHAR2(20),

  -- Mesures
  montant_ttc           NUMBER(9,2) DEFAULT 0 NOT NULL,   -- additive
  montant_ht            NUMBER(9,2) DEFAULT 0 NOT NULL,   -- additive
  montant_remise        NUMBER(9,2) DEFAULT 0 NOT NULL,   -- additive
  nb_mois_factures      NUMBER(3)   DEFAULT 0 NOT NULL,   -- additive
  delta_abonnes         NUMBER(1)   NOT NULL
                        CHECK (delta_abonnes IN (-1, 0, 1)),  -- additive
  revenu_cumule_abonne  NUMBER(11,2),                     -- semi-additive (date)
  anciennete_mois       NUMBER(4),                        -- non additive
  taux_remise           NUMBER(5,4)                       -- non additive (0 à 1)
);

-- ============================================================
--  3. Vues virtuelles sur les dimensions partagées
-- ============================================================

-- Avant de commencer à écrire comme un fou, petit point explicatif, ma table de faits à deux clés qui pointent
-- vers la même table dim_date : date_evenement_sk et date_souscription_sk. Si on veut les 2 dans une seule et même
-- requête, on doit joindre la table deux fois. Ça fonctionne, mais le résultat contient deux colonnes qui s’appellent 
-- toutes les deux mois. On ne sait plus laquelle est laquelle, et on risque de se tromper d’alias. On va donc faire
-- 2 vues ce sera plus pratique. DIM_LECTEUR est historisée (SCD 2). Une vue expose uniquement les versions courantes, 
-- ce dont la plupart des analyses ont besoin

-- Rôle 1 de DIM_DATE : date de l'événement
CREATE OR REPLACE VIEW v_date_evenement AS
SELECT date_sk             AS date_evenement_sk,
       date_complete       AS date_evenement,
       jour_semaine        AS jour_semaine_evenement,
       est_weekend         AS est_weekend_evenement,
       mois                AS mois_evenement,
       libelle_mois        AS libelle_mois_evenement,
       trimestre           AS trimestre_evenement,
       annee               AS annee_evenement,
       est_jour_ferie      AS est_ferie_evenement,
       periode_commerciale AS periode_commerciale_evenement
FROM dim_date;

-- Rôle 2 de DIM_DATE : date de souscription initiale
CREATE OR REPLACE VIEW v_date_souscription AS
SELECT date_sk       AS date_souscription_sk,
       date_complete AS date_souscription,
       mois          AS mois_souscription,
       libelle_mois  AS libelle_mois_souscription,
       trimestre     AS trimestre_souscription,
       annee         AS annee_souscription,
       annee || '-' || LPAD(mois, 2, '0') AS cohorte   -- ex. '2026-01' (à vérifier je suis pas sûr de mon coup)
FROM dim_date;

-- DIM_LECTEUR : versions courantes uniquement (SCD 2)
CREATE OR REPLACE VIEW v_lecteur_courant AS
SELECT *
FROM dim_lecteur
WHERE fin_validite = DATE '9999-12-31';

-- ============================================================
--  4. Données de test (instance du rapport) (évidemment par IA)
-- ============================================================

-- DIM_DATE
INSERT INTO dim_date VALUES (20240110, DATE '2024-01-10', 'Mercredi', 'Non', '2024-S02', 1, 'Janvier', 1, 1, 2024, 'Non', NULL);
INSERT INTO dim_date VALUES (20260110, DATE '2026-01-10', 'Samedi',   'Oui', '2026-S02', 1, 'Janvier', 1, 1, 2026, 'Non', 'Soldes d''hiver');
INSERT INTO dim_date VALUES (20260115, DATE '2026-01-15', 'Jeudi',    'Non', '2026-S03', 1, 'Janvier', 1, 1, 2026, 'Non', 'Soldes d''hiver');
INSERT INTO dim_date VALUES (20260215, DATE '2026-02-15', 'Dimanche', 'Oui', '2026-S07', 2, 'Février', 1, 1, 2026, 'Non', NULL);

-- DIM_HEURE
INSERT INTO dim_heure VALUES (5,    0,  5, 'Nuit', 'Non', 'Non');
INSERT INTO dim_heure VALUES (1240, 12, 40, 'Midi', 'Oui', 'Non');
INSERT INTO dim_heure VALUES (2130, 21, 30, 'Soir', 'Non', 'Non');

-- DIM_LECTEUR
INSERT INTO dim_lecteur VALUES (1001, 'C-784512', '18-24 ans', 'Étudiant', 'Oui', '5-15 min',  '30-60 min', 'International',
                                DATE '2026-01-05', DATE '2026-01-15', DATE '9999-12-31');
INSERT INTO dim_lecteur VALUES (1002, 'C-120877', '55-64 ans', 'Cadre',    'Non', '15-30 min', '1-2 h',     'Économie',
                                DATE '2023-11-20', DATE '2024-01-10', DATE '9999-12-31');

-- DIM_OFFRE
INSERT INTO dim_offre VALUES (12, 'NUM-ESS-M', 'Numérique Essentiel mensuel', 'Non', 'Numérique', 'Mensuelle', 11.99,  0, NULL,
                              DATE '2024-03-01', 'Oui');
INSERT INTO dim_offre VALUES (20, 'NUM-INT-A', 'Numérique Intégral annuel',   'Oui', 'Numérique', 'Annuelle',  199.00, 12, 'Courrier international',
                              DATE '2022-09-01', 'Oui');

-- DIM_PROMOTION
INSERT INTO dim_promotion VALUES (0, NULL, 'Aucune promotion', NULL, NULL, 0, NULL, NULL, NULL, NULL, NULL);
INSERT INTO dim_promotion VALUES (3, 'PREMIER1E', '1 € le premier mois', 'Prix fixe', 1.00, 1, 1.00, 'Tous',
                                  DATE '2026-01-01', DATE '2026-01-31', 'Soldes d''hiver');

-- DIM_GEOGRAPHIE
INSERT INTO dim_geographie VALUES (690, 'France', 'France métropolitaine', 'Auvergne-Rhône-Alpes', 'Rhône (69)',
                                   'Lyon', 'Lyon 3e', '69003', '69383');
INSERT INTO dim_geographie VALUES (350, 'France', 'France métropolitaine', 'Bretagne', 'Ille-et-Vilaine (35)',
                                   'Rennes', 'Rennes', '35000', '35238');

-- DIM_CANAL
INSERT INTO dim_canal VALUES (5, 'Paywall article',     'Paywall',    'Web', 'Mobile',     'Non', 'lemonde.fr',          'paywall', NULL,          NULL, 0);
INSERT INTO dim_canal VALUES (8, 'Newsletter matinale', 'Newsletter', 'Web', 'Ordinateur', 'Non', 'newsletter_matinale', 'email',   'La Matinale', NULL, 0);

-- DIM_TYPE_EVENEMENT
INSERT INTO dim_type_evenement VALUES (1, 'Souscription',   'Entrée',   NULL,   'Abonné',  'Carte', 'Accepté', 'Non', 'Non');
INSERT INTO dim_type_evenement VALUES (2, 'Renouvellement', 'Maintien', NULL,   'Système', 'Carte', 'Accepté', 'Non', 'Non');
INSERT INTO dim_type_evenement VALUES (3, 'Résiliation',    'Sortie',   'Prix', 'Abonné',  NULL,    NULL,      'Oui', 'Non');

-- FAIT_EVENEMENT_ABONNEMENT (evenement_id est généré automatiquement)
INSERT INTO fait_evenement_abonnement
  (date_evenement_sk, date_souscription_sk, heure_sk, lecteur_sk, offre_sk, promotion_sk, geo_sk, canal_sk, type_evenement_sk,
   num_contrat, num_transaction,
   montant_ttc, montant_ht, montant_remise, nb_mois_factures, delta_abonnes, revenu_cumule_abonne, anciennete_mois, taux_remise)
VALUES (20260115, 20260115, 1240, 1001, 12, 3, 690, 5, 1, 'CT-5001', 'TR-90001',
        1.00, 0.98, 10.99, 1,  1,   1.00,  0, 0.9166);   -- F1 : souscription avec promotion

INSERT INTO fait_evenement_abonnement
  (date_evenement_sk, date_souscription_sk, heure_sk, lecteur_sk, offre_sk, promotion_sk, geo_sk, canal_sk, type_evenement_sk,
   num_contrat, num_transaction,
   montant_ttc, montant_ht, montant_remise, nb_mois_factures, delta_abonnes, revenu_cumule_abonne, anciennete_mois, taux_remise)
VALUES (20260215, 20260115, 5, 1001, 12, 0, 690, 5, 2, 'CT-5001', 'TR-90417',
        11.99, 11.74, 0.00, 1,  0,  12.99,  1, 0);       -- F2 : renouvellement plein tarif

INSERT INTO fait_evenement_abonnement
  (date_evenement_sk, date_souscription_sk, heure_sk, lecteur_sk, offre_sk, promotion_sk, geo_sk, canal_sk, type_evenement_sk,
   num_contrat, num_transaction,
   montant_ttc, montant_ht, montant_remise, nb_mois_factures, delta_abonnes, revenu_cumule_abonne, anciennete_mois, taux_remise)
VALUES (20260110, 20240110, 2130, 1002, 20, 0, 350, 8, 3, 'CT-1187', NULL,
        0.00, 0.00, 0.00, 0, -1, 398.00, 24, NULL);      -- F3 : résiliation

COMMIT;

-- ============================================================
--  5. Requête de test : événements et solde net par mois,
--     en passant par la vue du rôle « date de l'événement »
--     (cf la partie 3 où j'ai fait ma vue)
-- ============================================================
SELECT de.mois_evenement,
       t.type_evenement,
       COUNT(*)             AS nb_evenements,
       SUM(f.delta_abonnes) AS solde_net
FROM fait_evenement_abonnement f
JOIN v_date_evenement   de ON f.date_evenement_sk = de.date_evenement_sk
JOIN dim_type_evenement t  ON f.type_evenement_sk = t.type_evenement_sk
WHERE de.annee_evenement = 2026
GROUP BY ROLLUP (de.mois_evenement, t.type_evenement)
ORDER BY de.mois_evenement, t.type_evenement;

-- Les lignes avec un type vides sont les sous-totaux de ROLLUP, et la dernière c'est le total