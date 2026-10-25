1. automatic provisioning and deployment (ca. 16 Stunden)

    today only the vaultwarden **image** updates itself, daily, via
    [monitoring/vaultwarden-autoupdate.sh](monitoring/vaultwarden-autoupdate.sh). everything in this
    repo, so compose files, monitoring scripts and cron entries, reaches the vps only when someone
    runs `git pull` in `/opt/docker` by hand. a merged commit therefore does nothing until deployed
    manually, which is the same silent-drift class the monitoring work removed for image versions.

    decided on 2026-09-03: push-based github action. a pull-based self-update cron job on the vps was
    the cheaper alternative at ca. 5 Stunden and was considered and rejected, because the action gives
    a deployment record per merge and gated deploys. do not re-open that comparison without a reason.

    1. move credentials from vps to [docs/vaultwarden.md](docs/vaultwarden.md)
    2. github action on merge to main:
        1. pull credentials from vaultwarden
        2. provision vps (idempotent)
        3. deploy to vps (upload from within github action to vps)
        4. cd /opt/docker && docker-compose pull && docker-compose up -d
    3. blocked on 1.1, which is circular: the action needs an ssh deploy key or equivalent to reach
       the vps, and the credentials it would read live in the vault it is deploying. break the loop by
       storing the deploy key as a github secret directly, not via vaultwarden
    4. a config deploy touches every service at once, unlike the vaultwarden image update which
       touches one. it needs the same discipline as
       [monitoring/vaultwarden-autoupdate.sh](monitoring/vaultwarden-autoupdate.sh): health-check
       after apply, and on failure `git reset --hard` to the previous commit plus a loud mail
2. connect google drive <-> [docs/dolibarr.md](docs/dolibarr.md) <-> shopware if possible
    1. **the dolibarr half now has a read path.** [tools/dolibarr/doli.sh](tools/dolibarr/doli.sh)
       reads the rest api with a dedicated api user, see
       [docs/dolibarr.md](docs/dolibarr.md#api-access). shopware's read side is already documented in
       [docs/shopware/admin-api.md](docs/shopware/admin-api.md). what is missing is the drive side and
       a decision on what should actually flow between the three, because "if possible" was never
       turned into a list of records (`decision`, ca. 2 Stunden)
    2. **the write path exists now for person records**, see
       [tools/dolibarr/set-address.sh](tools/dolibarr/set-address.sh). setup values stay a ui job,
       because `/setup/company` is `GET` only, measured against the live instance on 2026-09-14
    3. **the projects, tasks and tickets write path exists too**, see
       [tools/dolibarr/sync-pm.sh](tools/dolibarr/sync-pm.sh) and
       [docs/dolibarr.md](docs/dolibarr.md#projects-tasks-and-tickets). the backlog is a gitignored
       json spec, because the real one names people and links private documents. the script creates
       and updates and never deletes. it closes, cancels and reopens tickets through the PmTools
       module since 1.77.0, while closing a task stays a ui job. every run ends with a read back of
       tickets closed in the ui and tickets the spec does not name, since 1.82.0
3. [docs/shopware/TODO.md](docs/shopware/TODO.md)
4. maybe add nextcloud (docker-compose.yml)
5. [docs/minecraft.md](docs/minecraft.md)
    1. auto-detect minecraft version from the mods in the modlist (the docker minecraft server in use already has
       this functionality, but it had a bug; that should be fixed by now)
    2. 35 of the 63 tracked files under `minecraft-data/config/` are luckperms translation files,
       downloaded artifacts in 27 languages rather than configuration. every file under
       `minecraft-data/` arrived in one commit and none has been edited since, so nothing
       there is hand-maintained. untracking the translations is cleanup with no security value, and it
       makes the next `git pull` on the host delete them, so it is not free (ca. 15 Minuten)
    3. `ops.json` and `whitelist.json` are tracked and hold **five** distinct Minecraft usernames with
       their UUIDs, not four. counted on 2026-09-13: `bestcodename`, `Boehmb0Ss`, `DCXI`, `Emirgfk`
       and `NABI`, several of them appearing twice with an offline and an online uuid. the same names
       are already in `docker-compose.yml` under `OPS` and `WHITELIST`, which is where the image reads
       them from, so untracking the two json files alone would change nothing. these are pseudonyms
       rather than real names and no credential, so it is a disclosure decision for the owner and not
       a leak. **one of the five reads like a surname with digits in it**, which is the only one worth
       a second look before this is settled (`decision`)
6. security follow-ups from the 2026-09-07 ssh hardening ([docs/ssh-hardening.md](docs/ssh-hardening.md))
    1. move the accounts still on pbkdf2 to argon2id. the kdf is per-account and only its holder can
       change it, so this is a message to those people rather than an action here. **which accounts
       they are and what they hold is deliberately not written down**, here or in
       `sdwa5/docs/services.md`, because read beside a reachable `vault.sdwa5.org` it names the soft
       target and prices it. the admin panel has it for anybody who should (ca. 15 Minuten)
    2. finish the emergency access enrolment with the new member, in progress since 2026-09-08, so the
       org has a recovery path that does not depend on one master password. the grantee count is the
       thing to check in the admin panel and is not written down here, for the same reason as 6.1
       (ca. 30 Minuten)
    3. ipv6 drops out for minutes at a time and recovers on its own. the first time was 2026-09-08 and
       the second was 2026-10-15, from at least 01:43 to 01:52 Berlin time. measured during the second:
       the host kept its address and its static default route via `fe80::1`, echo requests and tcp syns
       left `eth0` with the right source, and the gateway answered neighbour discovery from ca. 01:47,
       yet tcpdump saw no reply or icmp error come back. the next hop `2a02:c206::1eaf` did not answer
       either. from outside, the home line and the company vpn exit both failed while their own ipv6
       controls worked. the host firewall is ruled out, because tcpdump reads ingress before netfilter
       and a firewall restart at 01:53 reproduced nothing over three minutes. no aaaa record is
       published, so no site was affected. **it happened a third and a fourth time on 2026-10-16**, around
       03:40 and 15:35 Berlin, each for ca. 25 s: inbound probes and the host's own outbound v6 failed while
       `fe80::1` sat REACHABLE in neighbour discovery, and ipv4 was unaffected. dockerd's `disable_ipv6`
       lines at container starts (02:21-02:46 and 15:14) are not a measured cause. so the trigger for the
       contabo ticket is reached. the 24-hour SEC-28 review on 2026-10-18 has 1452 samples and confirms
       a further both-target failure at 14:03 with ipv4 working and neighbour REACHABLE. the raw evidence
       and a German Contabo draft are retained privately; the temporary cron is retired. the remaining
       action is for the operator to submit the request, then track Contabo's answer. see the
       [measurement result](docs/monitoring.md#ipv6-reachability-log) (ca. 15 Minuten)
    4. **DONE on 2026-09-13.** `/opt/docker` had been unable to pull since the 2026-09-12 move: its
       `origin` still named the deleted personal repository and its `HEAD` was a pre-rewrite commit
       that existed nowhere. Nothing noticed, because deploys are manual. It now tracks
       `git@github.com:SdWa5/vps.git` at 1.32.0, `git pull --ff-only` succeeds unattended, and all six
       containers stayed up throughout, since the change touched only documentation and no compose
       file, monitoring script or hardening config.

       **Two things had to be fixed before the remote worked, and both are worth keeping.**

       **The organization disallowed deploy keys.** `deploy_keys_enabled_for_repositories` was `false`
       on `SdWa5`, which is GitHub's default for a new organization, so no key could be added to any
       repository in it. A personal repository has no such setting, which is why this only appeared
       after the move. It is now `true`. That is an organization-wide loosening and it is the right
       one here, because the alternative is a personal access token in a file on a public-facing host,
       where a deploy key is read-only and reaches exactly one repository.

       **The old deploy key could not be re-registered.** Deleting the personal repository took its
       deploy key with it, and GitHub then refused the same public key everywhere with
       "key is already in use" although it appears on no repository and on no account we can see. A
       fresh keypair `id_ed25519_sdwa5vps` was generated on the host instead and registered read-only,
       and `/root/.ssh/config` points at it. The dead `id_ed25519_deploy` pair was removed from the host on
       2026-09-13, after checking that nothing referenced it and that its public half was not in
       `authorized_keys`, so it granted no inbound access either.

       **The old key is attached to the soft-deleted repository, and that is the whole of "key is
       already in use".** Diagnosed 2026-09-13 from four observations that one explanation fits: on
       2026-09-13 the key still authenticated and GitHub greeted it `Hi bestcodename/sdwa5-vps!`, which
       is the greeting for a deploy key rather than an account key; that repository answers 404; the key
       is on none of the seven repositories this account can admin and on no account key; and GitHub
       refuses to register it anywhere. A deleted repository is restorable for 90 days, so its record
       and its deploy keys survive the delete while the REST API already reports 404.

       It is **not a security problem**. It is a read-only key on a repository that serves nothing, and
       its only private half was removed from this host on 2026-09-13. The registration lapses on its
       own when the retention window closes, around **2026-12-11**. The test that confirms the
       diagnosis is to try adding fingerprint `SHA256:9cc+0NXJEYRo7xyJ2WeTAFQbE94nDbCap3kgNdX39IU` as a
       deploy key in mid-December; if it is accepted then, this was the cause (`decision`, ca. 5 Minuten)

    5. **Six deleted repositories are still restorable, so the pre-rewrite history is unreachable rather
       than destroyed.** This is the one place the go-public work overstated itself, corrected
       2026-09-13. `bestcodename/sdwa5`, `sdwa5-vps` and `sdwa5-3d` were deleted on 2026-09-12, and
       `SdWa5/docs-old`, `vps-old` and `3d-old` on 2026-09-13. GitHub restores a deleted repository
       within 90 days, so every one of them can be brought back until roughly **2026-12-11**, with the
       private email address in 74 commits and the board members' names in theirs.

       **What the verification actually proved.** Fetching a pre-rewrite SHA from each new repository
       returns `not our ref`, with a control fetch proving the test works. That establishes that the
       live repositories do not serve those objects, which is the risk that mattered, because a reader
       holding an old hash cannot pull it. It does not establish destruction, and "cache cleared" was
       written as though it did.

       **It is not a publication blocker.** Restoring needs owner or organization-admin credentials, so
       there is no route to it from outside. What it does change is the honesty of the claim: for an
       exercise about other people's personal data, "GitHub retains a restorable copy until December"
       is a different sentence from "it is gone". Decided on 2026-10-17: the window closes on its own,
       and after 2026-12-12 a check confirms that the six are gone from
       <https://github.com/settings/repositories> and the organization's equivalent, together with the
       deploy key test in 6.4 (ca. 10 Minuten)

       **A history rewrite breaks this again**, because the host's `HEAD` stops existing. The repair is
       `fetch` plus `reset --hard` and never a re-clone, since `/opt/docker` carries the untracked
       runtime state of the whole stack, `minecraft-data` alone being 6.9 GiB. Check the deletions with
       `git diff --name-status HEAD origin/main` first; a tracked file that has since become untracked,
       as `minecraft-data/server.properties` once was, gets removed by the reset whatever `.gitignore`
       says afterwards.
7. **the Chimo Diazz deploy cannot install a plugin that is not already in the checkout**
   ([docs/chimodiazz.md](docs/chimodiazz.md)). `monitoring/chimodiazz-deploy.sh` runs
   `plugin:refresh`, `plugin:update`, `theme:compile` and `cache:clear`, and deliberately no
   `composer install`. A theme change therefore deploys itself, while a plugin that
   `chimodiazz/website` requires through composer, or one bought in the Shopware store, has to be
   installed on the host by hand. That breaks the property the rest of this pipeline has, namely that
   the shop's state follows from the repository. Raised on 2026-09-16, when a dark mode plugin came
   up. Dark mode itself belongs in the theme's own scss rather than here.

   Two halves, and they are separate decisions:

    1. composer requires from the plugin. running `composer install` in the container on every deploy
       is the obvious move and the dangerous one, because it reaches the network from a production
       shop, it can fail halfway, and the rollback would have to undo it as well. A safer shape runs
       it only when `composer.lock` moved, behind the same rollback, with the vendor directory
       snapshotted first (ca. 6 Stunden)
    2. store-bought plugins. These come from `packages.shopware.com` through composer, which
       `sdwa5.org` does since 2026-10-01 with its own shop token in an untracked `auth.json`, see
       [docs/shopware/plugins.md](docs/shopware/plugins.md). Chimo Diazz would need the composer
       token of its own shop, and installing it on deploy is then the same question as half 1. What
       is still wanted is a check that alerts when a plugin lands in `custom/plugins/` through the
       admin's plugin manager instead, because that one is locked as a path and not reproducible
       (ca. 4 Stunden)
   With #22 this would be settled by the image build, which runs `composer install` once per release
   instead of on the live shop.
8. **Chimo cannot see what his own deploy did.** Deployment is a pull from this side, so a push into
    `chimodiazz/website` is handed over and then goes quiet. `monitoring/chimodiazz-deploy.sh` runs
    every five minutes, writes no state file and no log that anything off this host can read, and its
    only output is a mail to the monitoring recipient when a run fails. Read in the script on
    2026-09-17, where those seven `send_mail` calls are the whole of it. His cloud Claude Code session
    therefore has no way to learn which commit is checked out, whether the last `theme:compile`
    succeeded, or why a rollback happened, and the admin API and the `Chimo agent MCP` integration
    reach the shop's data while saying nothing about the deploy. Raised on 2026-09-17.

    **The constraint is that whatever is granted reaches this one instance and nothing else.** A shell
    account is what that rules out, because `/opt/docker` carries every service in this repository. It
    does not rule out SSH itself, which is proposal 1 below. A reader on the monitoring mailbox is
    ruled out as well, because `MONITOR_MAIL_TO` is one address for the whole host and receives the
    health, backup and vaultwarden mails too.

    Four proposals, and they are alternatives rather than steps:

    1. **a forced-command SSH key that can only talk to this instance.** Measured on the host on
       2026-09-17, the ground is favourable. sshd has no `AllowUsers`, no `AllowGroups`, no
       `DenyUsers` and not a single `Match` block, `PasswordAuthentication` is already `no`, the
       `docker` group exists with **zero members** because everything here runs as root, and the only
       human uid is `admin` at 1000 with `/usr/sbin/nologin`. The shape is then a fresh account with
       no password and no `sudo` group membership, his own public key in its `authorized_keys` behind
       `restrict,command="…"`, a `Match User` block that repeats `ForceCommand`, `PermitTTY no` and
       `AllowTcpForwarding no` so that an edited `authorized_keys` cannot widen it, and one
       `/etc/sudoers.d` line naming a single root-owned helper with no wildcard in it.

       **The `docker` group is not the way in and staying out of it is the whole point**, because a
       member of it bind-mounts `/` into a container and is thereby root on this host. The wrapper
       maps a verb out of `SSH_ORIGINAL_COMMAND` onto a fixed `case` and hands the privileged half no
       string it received from the network, and it names `chimodiazz_shopware` and `chimodiazz-src`
       literally, so nothing it can be asked for reaches vaultwarden, dolibarr, minecraft or the
       `sdwa5.org` shop. The verbs worth having are the deploy state, the tail of the last run, a
       `--force` redeploy under the lock the script already takes, and an allowlist of exact
       `bin/console` subcommands.

       This is the only proposal that lets him act rather than only watch, and it opens no new public
       endpoint and puts no token on a public name. What it costs is a shell script parsing a remote
       string, where a quoting bug is root, so it is also the one that has to be written carefully and
       covered by the `tests/` suite. The private half would live wherever his cloud session keeps it,
       which is the weakest part of the arrangement and the reason the scope is drawn this tightly,
       because losing that key should cost the shop and nothing else. Revocation is one line out of
       `authorized_keys`. **Worth doing in the same pass is an `AllowGroups`**, since today any
       account on this host that has a key can log in, and that was acceptable while there was only
       one such account (ca. 6 Stunden)
    2. **a status file that the deploy script writes and Caddy serves.** Each run would record the
       branch, the commit, the timestamp, the outcome and, on a failure, the tail of the command that
       failed, as JSON somewhere under `/opt/docker`, and a `handle` in the `chimodiazz.sdwa5.org`
       block would serve that one path behind a bearer token. It reads nothing outside this instance,
       it opens no port and no account, and an agent can poll it. What it needs deciding first is
       whether commit hashes and build error output are fit to sit behind a single static token on a
       public name, and whether a failing `theme:compile` may quote plugin source. The state file is
       worth building either way, because proposal 1 wants the same data to print (ca. 3 Stunden)
    3. **the same result written back to `chimodiazz/website` as a commit status**, which is where he
       is looking anyway and where an agent reads it without any new endpoint. It costs a token with
       write access to a repository this host does not own, which inverts the read-only direction that
       the pull deployment was chosen for in the first place. That is the reason to expect this one to
       be rejected rather than a detail to solve (ca. 4 Stunden)
    4. **a second recipient for this script alone**, by setting `MONITOR_MAIL_TO` in
       `/etc/cron.d/chimodiazz-deploy` rather than in `.env`, so the deploy mails reach him and the
       rest of the host's monitoring does not. It is the cheapest of the four and it closes the human
       half only, because a mailbox is not something his session reads (ca. 30 Minuten)
9. **Paperless-ngx follow-ups** ([docs/paperless.md](docs/paperless.md)). Two instances, one for the
    Verein and one for the household, live on prod since 2026-10-16 (ca. 2 Stunden 15 Minuten for what is left)
    0. waiting for the second household account (priority low, ca. 10 Minuten). It was invited to the household
       Vaultwarden organization on 2026-10-17, which holds the household logins. Once the invitation is accepted, an
       owner confirms it in the web vault or with `bw confirm org-member` after an unlock. Then the account logs in
       to paper.ripper.sdwa5.org once and enrolls TOTP. All other logins have TOTP since 2026-10-16
    1. maybe fork paperless-ngx into the SdWa5 organization rather than running the upstream image
       unchanged. Nothing asks for a code change yet, so a fork is worth it only once one does,
       because every upstream release then has to be merged by hand (`decision`)
    2. make the fork public. Paperless-ngx is GPL-3.0, and publishing the modified source keeps the
       fork in line with it and with the plan to take all sdwa5 repositories public
    3. photograph all paper documents and upload them, Verein papers to paper.sdwa5.org and household papers
       to paper.ripper.sdwa5.org. A Paperless mobile app uploads straight from the phone, and the uploader
       becomes the owner. Household papers may go in, because the Contabo panel login, which reaches both
       instances, has 2FA enabled. The effort depends on the size of the pile, which is not counted yet
10. **BankSync follow-ups** ([docs/dolibarr.md](docs/dolibarr.md#custom-modules)). Live since 2026-10-05 in
    dry run at v1.2.0, account 4 mapped, opening balance 333.40 € matched PayPal, daily job at
    06:00 UTC, queue mail to mail@sdwa5.org
    1. switch on `BANKSYNC_AUTOPOST_ENABLED` after the first real `would_post` decisions were reviewed
11. **automate the SdWa5Theme deploy** ([docs/shopware/theme.md](docs/shopware/theme.md#deploy)) (ca. 2 Stunden
    30 Minuten). a theme change reaches sdwa5.org only through a hand-run `composer install`, `plugin:update`,
    `theme:compile` and `cache:clear` on the host. `monitoring/chimodiazz-deploy.sh` already does the rebuild,
    the health check and the rollback for Chimo Diazz. extract its rebuild and health helpers into a shared
    library at the theme's first update and run them for sdwa5.org as well. the script is not generalized as a
    whole, because its rollback runs `git reset --hard` on the whole checkout, and at `/opt/docker` that is
    every service in this repository
    Possibly settled by #22, if its rollout runs Shopware's deployment helper (plugin update and theme
    compile per release); to be checked when #22 is planned.
12. **the share links in the Chimo Diazz offcanvas menu share the site root on every page.** measured on
    2026-10-06 on a subpage of chimodiazz.sdwa5.org, where the share aside linked the subpage and the
    offcanvas linked `https://chimodiazz.sdwa5.org/`. the offcanvas is rendered inside the ESI header
    sub-request, so the request it reads its URL from is the header's own. the SdWa5Theme avoids it with a
    share row in the main content. the fix belongs in `chimodiazz/website`, by moving the offcanvas share
    links into the main content the same way or by dropping them. its aside builds the URL from
    `sw-storefront-url` and `resolved-uri`, which on sdwa5.org gave the technical `/navigation/<id>` path,
    so the aside probably shares the same wrong URL wherever Chimo Diazz has SEO URLs. SdWa5Theme 1.0.4 uses `sw-sales-channel-absolute-base-url` and
    `sw-original-request-uri` instead (ca. 30 Minuten)
13. also host gitlab and email myself (priority medium to low)
14. **host the sdwa5.org dns ourselves** (priority low, ca. 8 Stunden). today the domain and its dns sit
    at squarespace, and squarespace has no dns api. checked on 2026-10-16: it offers commerce apis only,
    its reseller apis are for approved partners, and its dns page drives an undocumented internal
    endpoint. every record is therefore a hand step in the squarespace ui
    1. the goal is an authoritative server with an api on the vps, e.g. powerdns with its http api in
       a container, and the zone as code in this repo behind a dry-run-by-default sync script like
       [tools/dolibarr/sync-pm.sh](tools/dolibarr/sync-pm.sh)
    2. it needs a secondary nameserver off the vps, because otherwise a dead vps also takes down the mx
       lookup for the google workspace mail. port 53 over udp and tcp opens on the firewall, and the
       server answers authoritatively only and with response rate limiting
    3. dnssec is off today (no ds, no dnskey), so the nameserver switch needs no key rollover
    4. a zone cannot be listed over dns, so the squarespace page is the inventory. visible from outside
       on 2026-10-16 were a records for the apex, `vault`, `erp`, `chimodiazz`, `paper` and
       `paper.ripper`, mx `1 smtp.google.com`, the apex txt `sw-domain-hash` and spf, and the
       `google._domainkey` dkim. there is no `www`
    5. deSEC (deSEC e.V., Berlin, free, rest api, tokens scoped per rrset) was considered as an api
       interim and set aside on 2026-10-16, because self-hosting is the goal
    6. side finding. no `_dmarc` record exists
15. optimize memory and swap ([docs/infrastructure.md](docs/infrastructure.md#memory--swap)) (priority medium).
    zram and the swapfile overflow are already set up, and zswap is unavailable because the debian cloud
    kernel is built without it
    1. tune the sysctls for zram first. `vm.swappiness=60` and `vm.page-cluster=3` are still the debian
       defaults, while a zram-first setup usually runs a swappiness of ca. 100 to 180 and
       `page-cluster=0`, because readahead from compressed ram buys nothing. measure swap use and
       latency before and after rather than taking the values on trust
    Measure again after #22, which drops dockware's bundled Apache, MySQL and MailCatcher.
16. **`apt autoremove` from 20.10.2026,** after a few quiet days on Debian 13. Removes the old 6.1
    kernels and the leftover Bookworm libraries. Measured 2026-10-24, the simulation removes 50 packages,
    now also the Python libraries cloud-init left behind, and none of `python3`, `netplan.io`,
    `openssh-server`, `sudo` or `cron` (ca. 10 Minuten)
17. **FOSS Dolibarr module for ticket dependencies and merges** (priority medium,
    [docs/dolibarr.md](docs/dolibarr.md#projects-tasks-and-tickets)). This becomes phase 3b of the
    PmTools module ([SdWa5/dolibarr-pmtools](https://github.com/SdWa5/dolibarr-pmtools)), live on
    production since 2026-10-16, and targets Dolibarr 24 rather than 23.0. Dolibarr has no
    ticket-to-ticket relation, so "blocks / blocked by" and merges are message lines today. The module
    adds a `blocks` relation with a block on the ticket card and in the list, a merge action that moves
    the message and closes the merged ticket, and REST endpoints so `sync-pm.sh` can write both.
    Publish it as an open-source module, deployed like BankSync via
    [tools/dolibarr/deploy-module.sh](tools/dolibarr/deploy-module.sh)
    1. check Dolistore and GitHub for an existing module first (ca. 30 Minuten)
    2. build, test against the 23.0 image and publish (ca. 24 Stunden)
18. **migrate the remaining Dolibarr workarounds into module endpoints**
    ([docs/dolibarr.md](docs/dolibarr.md#custom-modules)). The rule is to extend Dolibarr through its
    own module mechanism, never around it, and to migrate each workaround when its area is touched.
    Three remain
    1. the company address. `/setup/company` is `GET` only, so the address of the Verein itself is a
       ui job beside [tools/dolibarr/set-address.sh](tools/dolibarr/set-address.sh), which covers
       person records only. a PmTools route or a small module of its own would write it (ca. 3 Stunden)
    2. the `sdwa5-inventur` tools that pipe PHP through `docker exec`, namely the auslagen import, the
       kassenbuch and subscription dumps and the PayPal history. each becomes a module endpoint or a
       BankSync feature (ca. 16 Stunden)
    3. editing a membership subscription, which today is a recipe around `Subscription::update()`
       because the ui refuses reconciled lines and rewrites bank line dates. a module endpoint would
       wrap that call with its checks (ca. 4 Stunden)
19. **bring the Chimo Diazz shop back on Shopware 6.7.15.1 and PHP 8.5** ([docs/chimodiazz.md](docs/chimodiazz.md))
    (ca. 3 Stunden). It is switched off since 2026-10-24 and still runs 6.7.11.1 on PHP 8.2.31. The way
    back (`PHP_VERSION=8.5`, the mitigation ini mount, the cron files, the monitoring defaults and the
    Caddy proxy) is listed at the top of docs/chimodiazz.md. `composer audit --locked` with the vendored
    Composer reported 24 advisories in 9 packages on 2026-10-16. The procedure is the main shop's in
    [docs/shopware/infrastructure.md](docs/shopware/infrastructure.md#updating-shopware). The mirror reads
    its image only from `docker-compose.yml`, so for this shop it needs `SDWA5_SHOPWARE_DEV_IMAGE`,
    `SDWA5_SHOPWARE_HTML` and `SDWA5_SHOPWARE_ARCHIVE` set as well, which is untested. The site comes from
    the private `chimodiazz/website`, so the new lock presumably has to land there and needs Chimo's side
    Superseded if #22 lands first, since the production image covers both shops; the dockware route
    stays the fallback.
20. **Paperless AI features with a local model** ([docs/paperless.md](docs/paperless.md)) (ca. 4 Stunden).
    Paperless-ngx 3.x offers AI suggestions and a document chat behind `PAPERLESS_AI_ENABLED`, with Ollama
    as one of its backends, and both instances run with it off. `docker-compose.yml` already holds an
    `ollama` service as the inactive profile `ollama`, loopback-only on a network of its own. Paperless
    would need a network path to it, and document text would then never leave the VPS. RAM is the open
    question, because a model next to two shops and two Paperless instances on 5.9 GB needs measuring
    before it is switched on
21. **the Chimo Diazz shop never delivers a mail** ([docs/chimodiazz.md](docs/chimodiazz.md#dockwares-bundled-tools-were-public-and-are-not-any-more))
    (ca. 1 Stunde 30 Minuten). Measured 2026-10-16: its `core.mailerSettings.emailAgent` is empty, so
    Shopware falls back to `.env`'s `MAILER_DSN=smtp://127.0.0.1`, which is dockware's MailCatcher. Order
    confirmations and password resets land there. Give it the main shop's relay settings, check that the
    Workspace relay accepts its sender address, send a test mail, then set `SDWA5_STOP_MAILCATCHER=1` for
    it in `docker-compose.projects.yml` and adjust `CLOSED_LISTENERS` in `monitoring/security-recheck.sh`
    With #22 the relay settings become a step of Chimo's return, and the MailCatcher fallback disappears.
22. **a production image instead of dockware for both shops** (ca. 24 Stunden). dockware is a
    development image. `hardening/dockware-boot-end.sh` stops its sshd and MailCatcher on every boot, and
    Caddy blocks Adminer and the log viewer, but all of it is still installed, root and `dockware` keep
    their default passwords, and www-data has passwordless sudo. Shopware's own production template
    with a PHP-FPM image would remove that, and it also ends the root/root database login that
    `hardening/dockware-db-account.sh` has to keep for dockware's boot script. the image would also replace
    dockware's Composer 2.2.9 of 2022, which has no `audit` and misses the fixes for CVE-2024-24821 and
    CVE-2024-35241; the vendored Composer in `vendor/composer/composer` covers the audit until then
    Would also settle #7, #19 and #21, item 8 of [docs/shopware/TODO.md](docs/shopware/TODO.md), and a
    clean database stop at host shutdown, which dockware cannot give because it ignores SIGTERM.
23. **send the monitoring mails to one mailbox instead of two** ([docs/monitoring.md](docs/monitoring.md)).
    `MONITOR_MAIL_TO` in the vps `.env` lists the private Gmail address and ripper@sdwa5.org, so every
    health, backup and vaultwarden mail lands twice in Stefan's two main inboxes
    1. quick fix for now. set `MONITOR_MAIL_TO` to the private address alone and send a test mail with
       `monitoring/vps-health.sh`. the default in `monitoring/lib.sh` stays ripper@sdwa5.org, so it
       only applies when `.env` sets nothing (priority high, ca. 10 Minuten)
    2. later, a shared org IT mailbox it@sdwa5.org as the only recipient, and the default in
       `monitoring/lib.sh` and `.env.example` changed to it. whether the mailbox exists is unchecked, if not it gets
       created first, as a Workspace group or shared inbox. `/etc/cron.d/chimodiazz-deploy` is checked
       for an override of its own at the same time (priority medium, ca. 45 Minuten)
24. **share a single image from the Shopware image slider** (SdWa5Theme). The share links in
    `layout/share/share-links.html.twig` share the page only, and the image slider has no share action
    of its own, so one picture cannot be sent by its url or through the browser share sheet
    1. give each slide a url of its own, either the media url or the page url with a fragment that opens
       the slider on that slide. the fragment needs slider javascript to jump to the slide
    2. a share button per slide that calls `navigator.share` with that url, and the WhatsApp, Telegram
       and e-mail links as the fallback. the template notes that the deploy builds no storefront
       javascript, so this needs a storefront js build in the deploy first, or an inline script (ca. 6 Stunden)
25. **redirect `d.sdwa5.org` and `donate.sdwa5.org` to the PayPal donation page** ([docs/caddy.md](docs/caddy.md))
    (priority high, ca. 1 Stunde). The donation links on sdwa5.org point to `https://paypal.me/SdWa5`
    (measured 2026-10-16). Neither name has a DNS record yet
    1. two A records `d` and `donate` to 158.220.127.232 at Squarespace, entered by hand, since Squarespace
       has no DNS API (TODO #14)
    2. one Caddy block for both names with `redir https://paypal.me/SdWa5 302`, deployed only once the records
       resolve, because Caddy retries ACME forever on a name without DNS
    3. the two names in `security-recheck.sh` (HSTS and TLS) and `docs/caddy.md`. `RECHECK_SITES` expects a
       200, so the check has to accept the redirect to PayPal there
26. **change Dolibarr passwords through the API and the MCP server** ([docs/dolibarr.md](docs/dolibarr.md#mcp-server))
    (ca. 4 Stunden). Dolibarr 24 already accepts `pass` in `PUT /users/{id}`, given the `user > password`
    right or admin (`user/class/api_users.class.php`, read on 2026-10-16). `GET /users/{id}/setPassword`
    only generates a random password and needs `API_ENABLE_LOGIN_API` and `API_ALLOW_PASSWORD_RESET`, so
    it does not fit
    1. a `set-password` command beside [tools/dolibarr/doli.sh](tools/dolibarr/doli.sh) that reads the new
       password from a file or a pipe such as `<(bw get password ID)` and never prints it (ca. 1 Stunde 30 Minuten)
    2. an MCP tool for the same call through the `addMcpTools` hook of PmTools. Decide first whether an MCP
       client may change passwords at all, because the `mcp` user would need the password right for it
       (ca. 2 Stunden 30 Minuten)
27. **a new UI for Dolibarr that talks to it only over REST** (ca. 80 Stunden for a first version).
    Dolibarr's own UI hides common actions. The password change is the case found on 2026-10-16. Dolibarr 24
    has no button for it, the new password goes into the Password field of the Modify form
    (`user/card.php?id=<id>&action=edit`), and the **Reinit password** button generates a random one instead
    1. top-down. Layout and functionality are designed from the tasks the users actually do, independently
       of how Dolibarr structures its pages and menus. Dolibarr is the backend behind the REST API and the
       PmTools routes and does not shape the UI
    2. a missing endpoint is added to Dolibarr as a module route, never worked around in the UI (TODO #18).
       The password change uses the call of #26
    3. no change to the Dolibarr core, so the UI survives its upgrades
    4. open are the scope of a first version (which tasks), the stack, the hosting, and how it logs in, by an
       API key per user or through the login API, which is off today
28. **rename the PmTools module, since it becomes the general REST and MCP extension of Dolibarr**
    ([SdWa5/dolibarr-pmtools](https://github.com/SdWa5/dolibarr-pmtools),
    [docs/dolibarr.md](docs/dolibarr.md#custom-modules)) (ca. 6 Stunden). It started with the ticket
    routes and the ten `pm_*` MCP tools, and #18 and #26 add
    endpoints outside project management. The new name is open. A rename touches
    1. the module class `modPmTools`, its `rights_class` `pmtools`, the `MAIN_MODULE_PMTOOLS` constant and the
       `custom/pmtools` directory. The module number 500302 can stay, but Dolibarr keys the constant and the
       rights by name, so on prod the rename is probably an uninstall of the old module and an install of the
       new one, with the user rights granted again
    2. the REST route prefix and the MCP tool names, together with their callers
       [tools/dolibarr/sync-pm.sh](tools/dolibarr/sync-pm.sh) and the `mcp` user
    3. the GitHub repository (GitHub redirects the old url), `docs/dolibarr.md`, the README and #17
    4. decide first between the rename and a second module beside PmTools for the endpoints outside
       project management
29. (proposal) **move the Chimo Diazz shop off the host that runs Vaultwarden** ([docs/chimodiazz.md](docs/chimodiazz.md)).
    the isolation of 2026-10-15 keeps the shop's containers from reaching the vault, which
    `monitoring/security-recheck.sh` measures, but a container escape in a third-party shop would still
    land on the host that holds the vault. the proposal is a separate small vps for the shop, done as its
    own migration. it overlaps with #19 and #22 and waits while the shop is not an active project
    (ca. 6 Stunden)
30. **delete the evidence of the 2026-10-24 compromise check after 2026-11-23** (ca. 10 Minuten).
    `/root/forensics-20261024`, the `forensic/*:20261024` images and the Dolibarr 24.0.2 upgrade leftover
    `/var/tmp/archive-verify.calVSV` (94 MB, a copy of Dolibarr documents) on the host
31. (proposal) **state the server-log retention on the Datenschutz page** (ca. 15 Minuten). Its section
    "Speicherdauer" names no period for the IP address, browser and access times it lists under server logs.
    The Caddy access logs `/var/log/caddy/access-*.log` keep 14 days since 1.97.0, so the page would say
    "14 Tage".
32. (proposal) **sshd: `AllowUsers root` and an hourly check of the effective settings**
    ([docs/ssh-hardening.md](docs/ssh-hardening.md#login-accounts-and-roots-keys)). sshd takes a key for any
    account, and a `nologin` shell does not stop `ssh -N` port forwarding, which stays on for root's
    Vaultwarden tunnel. Today only root has a key file, and the account check watches only root's (measured
    2026-10-24). `AllowUsers root` in `10-hardening.conf` would close the other accounts. The recheck compares
    only that drop-in with the checkout, so a second drop-in or an edit to `sshd_config` could still add a key
    source such as `AuthorizedKeysCommand`, `TrustedUserCAKeys` or `AuthorizedPrincipalsFile`. The hourly part
    would read `sshd -T` and be CRIT on any of those, on password or keyboard-interactive login, and on a file
    in `sshd_config.d` other than `10-hardening.conf` (ca. 2 Stunden)
33. (proposal) **count primary groups in the account check** ([monitoring/account-check.sh](monitoring/account-check.sh)).
    The check reads only the member lists in `/etc/group`, while an account whose `/etc/passwd` group is
    `sudo` or `docker` is just as much a member. The check would compare the group ids too. `admin` (uid
    1000) has a private group of the same name, which is on the list of root-equivalent groups, so `admin`
    would leave that list. Debian's sudoers grants nothing to `%admin`, and a rule for it is already CRIT
    (ca. 45 Minuten)
34. (proposal) **a package integrity check** ([docs/monitoring.md](docs/monitoring.md)). `dpkg --verify` finds no
    changed file outside the config files today (measured 2026-10-24). A run in `vps-health.sh` that is CRIT on
    a changed package file would catch a replaced `sshd`, `sudo` or library, which no check covers now. Root can
    rewrite dpkg's checksums too, so it catches careless or partial tampering, not a full root compromise. Its
    run time decides between a daily and an hourly run (ca. 1 Stunde 30 Minuten)
35. (proposal) **review the access-log redaction from 2026-10-31** ([docs/caddy.md](docs/caddy.md#access-logs)).
    In the first hour only scanner parameters appeared, so the redacted names come from the applications' known
    links, not from traffic. The pattern matches exact names, so a name such as `_sw_payment_token` or
    `securekey` would pass unredacted, and so would a token percent-encoded inside a `next=` target. After a
    week, list the query parameter names per site, names and counts only, then add the secret ones to the
    `access_log` snippet and to the `logs:` probe (ca. 1 Stunde)
36. (proposal) **one site list for the access-log probe** ([tests/caddyfile.bats](tests/caddyfile.bats)). The
    sites live in the Caddyfile's `import access_log` lines and again in `ACCESS_LOG_SITES` of
    `security-recheck.sh`, so a new site without the second edit gets no `logs:` probe, and nothing says so. A
    bats test that compares the two lists would fail CI instead (ca. 20 Minuten)
37. (proposal) **test the console login with root's password once**
    ([docs/ssh-hardening.md](docs/ssh-hardening.md#login-accounts-and-roots-keys)). Root has a password
    (`passwd -S` shows `P`), but whether it logs in on the Contabo VNC console is untested, and that console is
    the way back after a lost key. It needs the password from the vault and the Contabo panel (ca. 15 Minuten)
