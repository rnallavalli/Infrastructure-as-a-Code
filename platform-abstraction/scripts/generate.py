#!/usr/bin/env python3
"""
YAML to Terraform Translator
Reads app-config.yaml and generates terraform.tfvars

Usage:
    python3 scripts/generate.py                       # uses ./app-config.yaml
    python3 scripts/generate.py --config my-app.yaml  # custom config
    python3 scripts/generate.py --validate-only       # validate only
    python3 scripts/generate.py --dry-run             # preview output
"""
import yaml, sys, os, json, ipaddress, argparse
from datetime import datetime
from pathlib import Path

COMPUTE_PROFILES = {
    "small":  {"cpu": 512,  "memory": 1024},
    "medium": {"cpu": 1024, "memory": 2048},
    "large":  {"cpu": 2048, "memory": 4096},
    "xlarge": {"cpu": 4096, "memory": 8192},
}
DB_PROFILES = {
    "small":  "db.r6g.large",
    "medium": "db.r6g.xlarge",
    "large":  "db.r6g.2xlarge",
}
VALID_ENVS = ["dev", "staging", "production"]

class ConfigValidator:
    def __init__(self, config):
        self.config = config
        self.errors = []
        self.warnings = []

    def validate(self):
        self._check_app()
        self._check_container()
        self._check_scaling()
        self._check_database()
        self._check_dns()
        self._check_certs()
        self._check_regions()
        self._check_network()
        return len(self.errors) == 0

    def _req(self, path, msg):
        keys = path.split(".")
        val = self.config
        for k in keys:
            if not isinstance(val, dict) or k not in val:
                self.errors.append(f"[MISSING] {path}: {msg}")
                return None
            val = val[k]
        if val is None or (isinstance(val, str) and not val.strip()):
            self.errors.append(f"[EMPTY] {path}: {msg}")
            return None
        return val

    def _check_app(self):
        name = self._req("app.name", "App name required")
        if name and not name.replace("-","").replace("_","").isalnum():
            self.errors.append("[INVALID] app.name: alphanumeric/hyphens/underscores only")
        if name and len(name) > 28:
            self.errors.append("[INVALID] app.name: max 28 chars (AWS limits)")
        env = self._req("app.environment", "Environment required")
        if env and env not in VALID_ENVS:
            self.errors.append(f"[INVALID] app.environment: must be one of {VALID_ENVS}")

    def _check_container(self):
        self._req("container.image", "Container image URI required")
        port = self.config.get("container", {}).get("port", 8080)
        if not (1 <= port <= 65535):
            self.errors.append("[INVALID] container.port: must be 1-65535")

    def _check_scaling(self):
        profile = self.config.get("scaling", {}).get("profile", "medium")
        if profile not in COMPUTE_PROFILES:
            self.errors.append(f"[INVALID] scaling.profile: must be one of {list(COMPUTE_PROFILES.keys())}")
        p = self.config.get("scaling", {}).get("primary", {})
        if p.get("min_tasks", 2) > p.get("max_tasks", 10):
            self.errors.append("[INVALID] scaling.primary: min > max")
        env = self.config.get("app", {}).get("environment", "")
        if env == "production" and p.get("min_tasks", 2) < 2:
            self.warnings.append("[WARN] Production should have min_tasks >= 2 for HA")

    def _check_database(self):
        self._req("database.name", "Database name required")
        profile = self.config.get("database", {}).get("profile", "medium")
        if profile not in DB_PROFILES:
            self.errors.append(f"[INVALID] database.profile: must be one of {list(DB_PROFILES.keys())}")
        ret = self.config.get("database", {}).get("backup_retention_days", 14)
        if ret < 1 or ret > 35:
            self.errors.append("[INVALID] backup_retention_days: must be 1-35")

    def _check_dns(self):
        self._req("dns.domain", "Domain required")
        self._req("dns.hosted_zone_id", "Route 53 hosted zone ID required")

    def _check_certs(self):
        self._req("certificates.primary", "Primary ACM cert ARN required")
        self._req("certificates.secondary", "Secondary ACM cert ARN required")
        for k in ["primary", "secondary"]:
            arn = self.config.get("certificates", {}).get(k, "")
            if arn and not arn.startswith("arn:aws:acm:"):
                self.errors.append(f"[INVALID] certificates.{k}: must be arn:aws:acm:...")

    def _check_regions(self):
        p = self.config.get("regions", {}).get("primary", "us-east-1")
        s = self.config.get("regions", {}).get("secondary", "us-west-2")
        if p == s:
            self.errors.append("[INVALID] regions: primary and secondary must differ")

    def _check_network(self):
        for k in ["primary_vpc_cidr", "secondary_vpc_cidr"]:
            cidr = self.config.get("network", {}).get(k, "")
            if cidr:
                try:
                    net = ipaddress.ip_network(cidr, strict=False)
                    if net.prefixlen > 20:
                        self.warnings.append(f"[WARN] network.{k}: /{net.prefixlen} may be too small")
                except ValueError:
                    self.errors.append(f"[INVALID] network.{k}: not a valid CIDR")

def calc_subnets(vpc_cidr):
    net = ipaddress.ip_network(vpc_cidr, strict=False)
    subs = list(net.subnets(new_prefix=24))
    if len(subs) < 24:
        return None
    return {
        "public":   [str(subs[0]), str(subs[1]), str(subs[2])],
        "private":  [str(subs[10]), str(subs[11]), str(subs[12])],
        "database": [str(subs[20]), str(subs[21]), str(subs[22])],
    }

def generate_tfvars(cfg):
    app = cfg.get("app", {}); ctr = cfg.get("container", {}); sc = cfg.get("scaling", {})
    db = cfg.get("database", {}); dns = cfg.get("dns", {}); certs = cfg.get("certificates", {})
    reg = cfg.get("regions", {}); net = cfg.get("network", {})
    comp = COMPUTE_PROFILES.get(sc.get("profile", "medium"))
    db_cls = DB_PROFILES.get(db.get("profile", "medium"))
    db_list = list(DB_PROFILES.keys())
    idx = db_list.index(db.get("profile", "medium"))
    db_cls2 = DB_PROFILES.get(db_list[max(0, idx - 1)])
    pvpc = net.get("primary_vpc_cidr", "10.0.0.0/16")
    svpc = net.get("secondary_vpc_cidr", "10.1.0.0/16")
    ps = net.get("primary_public_subnets") and {"public": net["primary_public_subnets"], "private": net.get("primary_private_subnets"), "database": net.get("primary_database_subnets")} or calc_subnets(pvpc) or {"public":["10.0.1.0/24","10.0.2.0/24","10.0.3.0/24"],"private":["10.0.11.0/24","10.0.12.0/24","10.0.13.0/24"],"database":["10.0.21.0/24","10.0.22.0/24","10.0.23.0/24"]}
    ss = net.get("secondary_public_subnets") and {"public": net["secondary_public_subnets"], "private": net.get("secondary_private_subnets"), "database": net.get("secondary_database_subnets")} or calc_subnets(svpc) or {"public":["10.1.1.0/24","10.1.2.0/24","10.1.3.0/24"],"private":["10.1.11.0/24","10.1.12.0/24","10.1.13.0/24"],"database":["10.1.21.0/24","10.1.22.0/24","10.1.23.0/24"]}
    p = sc.get("primary", {}); s = sc.get("secondary", {})
    fl = lambda l: json.dumps(l)
    img = f'{ctr.get("image","")}:{ctr.get("tag","latest")}'
    return f"""# Auto-generated from app-config.yaml on {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
# App: {app.get("name")} | Env: {app.get("environment")} | DO NOT EDIT - edit app-config.yaml

project_name = "{app.get("name","myapp")}"
environment  = "{app.get("environment","production")}"

primary_region   = "{reg.get("primary","us-east-1")}"
secondary_region = "{reg.get("secondary","us-west-2")}"

domain_name               = "{dns.get("domain","")}"
hosted_zone_id            = "{dns.get("hosted_zone_id","")}"
primary_certificate_arn   = "{certs.get("primary","")}"
secondary_certificate_arn = "{certs.get("secondary","")}"
health_check_path         = "{ctr.get("health_check","/health")}"

primary_vpc_cidr         = "{pvpc}"
primary_public_subnets   = {fl(ps["public"])}
primary_private_subnets  = {fl(ps["private"])}
primary_database_subnets = {fl(ps["database"])}

secondary_vpc_cidr         = "{svpc}"
secondary_public_subnets   = {fl(ss["public"])}
secondary_private_subnets  = {fl(ss["private"])}
secondary_database_subnets = {fl(ss["database"])}

container_image = "{img}"
container_port  = {ctr.get("port",8080)}
ecs_cpu         = {comp["cpu"]}
ecs_memory      = {comp["memory"]}

ecs_desired_count_primary = {p.get("desired_tasks",3)}
ecs_min_capacity_primary  = {p.get("min_tasks",2)}
ecs_max_capacity_primary  = {p.get("max_tasks",10)}

ecs_desired_count_secondary = {s.get("desired_tasks",1)}
ecs_min_capacity_secondary  = {s.get("min_tasks",1)}
ecs_max_capacity_secondary  = {s.get("max_tasks",6)}

aurora_engine_version           = "15.4"
db_name                         = "{db.get("name","appdb")}"
db_master_username              = "dbadmin"
aurora_primary_instance_class   = "{db_cls}"
aurora_primary_instance_count   = {db.get("primary_instances",2)}
aurora_secondary_instance_class = "{db_cls2}"
aurora_secondary_instance_count = {db.get("secondary_instances",1)}
aurora_backup_retention         = {db.get("backup_retention_days",14)}
"""

def main():
    parser = argparse.ArgumentParser(description="Translate app-config.yaml to Terraform tfvars")
    parser.add_argument("--config", default="app-config.yaml", help="Path to YAML config")
    parser.add_argument("--output", default=None, help="Output tfvars path")
    parser.add_argument("--validate-only", action="store_true", help="Validate only")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing")
    args = parser.parse_args()

    cfg_path = Path(args.config)
    if not cfg_path.exists():
        print(f"\n  x Config not found: {cfg_path}")
        print(f"    Copy template: cp app-config.yaml.example app-config.yaml\n")
        sys.exit(1)

    with open(cfg_path) as f:
        cfg = yaml.safe_load(f)
    if not cfg:
        print(f"\n  x Config file is empty\n"); sys.exit(1)

    v = ConfigValidator(cfg)
    ok = v.validate()
    name = cfg.get("app",{}).get("name","?"); env = cfg.get("app",{}).get("environment","?")

    print(f"\n  Validating: {name} ({env})")
    for w in v.warnings: print(f"    WARN  {w}")
    if v.errors:
        for e in v.errors: print(f"    FAIL  {e}")
        print(f"\n  Validation FAILED ({len(v.errors)} errors)\n"); sys.exit(1)
    print(f"    OK  All checks passed")

    if args.validate_only:
        print(f"\n  Validation OK\n"); sys.exit(0)

    tfvars = generate_tfvars(cfg)

    if args.dry_run:
        print(f"\n  --- Generated tfvars (dry run) ---")
        print(tfvars)
        print(f"  --- End dry run ---\n"); sys.exit(0)

    out = args.output or f"../terraform/environments/{env}.tfvars"
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w") as f: f.write(tfvars)

    comp = COMPUTE_PROFILES.get(cfg.get("scaling",{}).get("profile","medium"),{})
    db_cls = DB_PROFILES.get(cfg.get("database",{}).get("profile","medium"),"?")
    p = cfg.get("scaling",{}).get("primary",{})
    print(f"    Generated: {out}")
    print(f"    Profile:   {comp.get('cpu','?')} CPU, {comp.get('memory','?')} MB")
    print(f"    Database:  {db_cls}")
    print(f"    Primary:   {p.get('desired_tasks',3)} tasks ({p.get('min_tasks',2)}-{p.get('max_tasks',10)})")
    print(f"    Regions:   {cfg.get('regions',{}).get('primary','us-east-1')} / {cfg.get('regions',{}).get('secondary','us-west-2')}")
    print(f"\n  Ready to deploy: make apply\n")

if __name__ == "__main__":
    main()
