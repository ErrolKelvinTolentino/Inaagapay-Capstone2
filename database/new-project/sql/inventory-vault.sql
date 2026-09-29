-- Read only. Names only, never values. Run only when Vault is installed.
\o vault_secret_names.csv
SELECT name, description FROM vault.secrets ORDER BY name;
\o
