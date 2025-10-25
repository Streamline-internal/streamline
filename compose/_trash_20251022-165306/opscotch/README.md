Opscotch — Stack isolé (UI+backend) publié sur api.<domaine> via Caddy.
Commande utiles:
  cd /opt/streamline/compose/opscotch
  ./deploy.sh      # pull + up + attente healthy + smoke
  ./smoke.sh       # tests HTTP
  ./backup.sh      # dump Postgres
  ./restore.sh <archive.sql.gz>
  ./rollback.sh    # retag image précédente (si PREV_IMAGE_ID capturé)
