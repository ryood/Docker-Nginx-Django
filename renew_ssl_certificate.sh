#!/bin/bash
cd /home/ec2-user/pnpn/
docker compose run --rm certbot renew --dry-run
docker compose exec -T nginx nginx -t && \
docker compose exec -T nginx nginx -s reload

