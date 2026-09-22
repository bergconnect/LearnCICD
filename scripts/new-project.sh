#!/usr/bin/bash
# Uso: scripts/new-project.sh <Naam>  — legt een nieuwe service aan
# (code, tests, sln, version.json, projects.json, chart, ArgoCD-apps).
#
# Sjabloonbron is altijd Worker: code/tests worden byte-voor-byte gespiegeld
# via sed (alleen Worker→Naam), zodat SDK-vorm, PackageReferences,
# ProjectReference-backslashes en test-asserties nooit uit de pas lopen.
set -euo pipefail
NAAM="${1:?Gebruik: scripts/new-project.sh <Naam>}";
case "$NAAM" in ''|*[!A-Za-z0-9]*|[!A-Za-z]*)
echo "::error::Naam moet alfanumeriek zijn en met een letter beginnen";
exit 1;; esac;
if [ -e "src/$NAAM" ]; then
echo "::error::src/$NAAM bestaat al"; exit 1; fi;
KLEIN=$(echo "$NAAM" | tr '[:upper:]' '[:lower:]');
HOOGSTE=$(grep -h '"version"' src/*/version.json |
grep -o '[0-9]*\.[0-9]*' | cut -d. -f2 | sort -n | tail -1);
VOLGENDE=$((HOOGSTE + 1));
mkdir -p "src/$NAAM" "tests/$NAAM.Tests";
sed "s/Worker/$NAAM/g" src/Worker/Worker.csproj > "src/$NAAM/$NAAM.csproj";
sed "s/Worker/$NAAM/g" src/Worker/Program.cs > "src/$NAAM/Program.cs";
sed "s/Worker/$NAAM/g" tests/Worker.Tests/Worker.Tests.csproj > "tests/$NAAM.Tests/$NAAM.Tests.csproj";
sed "s/Worker/$NAAM/g" tests/Worker.Tests/HealthEndpointTests.cs > "tests/$NAAM.Tests/HealthEndpointTests.cs";
dotnet sln LearnCICD.sln add "src/$NAAM/$NAAM.csproj" "tests/$NAAM.Tests/$NAAM.Tests.csproj";
cat > "src/$NAAM/version.json" <<JS
{
  "version": "0.$VOLGENDE",
  "pathFilters": ["."],
  "publicReleaseRefSpec": [
    "^refs/heads/main$"
  ]
}
JS
jq --arg n "$NAAM" --arg i "$KLEIN" --arg c "$KLEIN" '. + {($n): {image_name: $i, chart: $c, paths: ["src/\($n)/**"], "test-paths": ["tests/\($n).Tests/**"]}}' .github/projects.json > /tmp/projects.json && mv /tmp/projects.json .github/projects.json;
cp -r .infra/learncicd-worker ".infra/$KLEIN";
grep -rl 'learncicd-worker' ".infra/$KLEIN" | xargs sed -i "s/learncicd-worker/$KLEIN/g";
for ENV in devtest productie; do
case "$ENV" in devtest) PORT=8080; VFILE=values_dev.yaml;; productie) PORT=8082; VFILE=values_prod.yaml;; esac;
printf 'service:\n  port: %s\nimage:\n  tag: ""\n' "$PORT" > ".infra/$KLEIN/$VFILE";
done;
for ENV in devtest productie; do
sed -e "s/learncicd-worker/$KLEIN/g" "argocd/applications/learncicd-worker-devtest.yaml" > "/tmp/app.yaml";
python3 - "$KLEIN" "$ENV" "$VFILE" <<'PY' > "argocd/applications/$KLEIN-$ENV.yaml"
import sys
txt = open('/tmp/app.yaml').read()
txt = txt.replace(f'{sys.argv[1]}-devtest', f'{sys.argv[1]}-{sys.argv[2]}')
txt = txt.replace('values_dev.yaml', sys.argv[3])
txt = txt.replace('namespace: devtest', f'namespace: {sys.argv[2]}')
print(txt, end='')
PY
done;
echo "Klaar. Verifieer met:";
echo "(cd src/$NAAM && dotnet nbgv get-version -v SemVer2)";
echo "helm lint .infra/$KLEIN -f .infra/$KLEIN/values.yaml -f .infra/$KLEIN/values_dev.yaml";
echo "dotnet test --project tests/$NAAM.Tests/$NAAM.Tests.csproj -c Release";
