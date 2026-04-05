import json
import subprocess
import os
import sys

# Configurações de Caminho
BASE_DIR = r"C:\CLMS\Github"
REPO_DIR = os.path.join(BASE_DIR, "repo")
MACHINE_JSON = os.path.join(BASE_DIR, "machine.json")
STATE_JSON = os.path.join(BASE_DIR, "state.json")
MANIFEST_JSON = os.path.join(REPO_DIR, "manifest.json")

def load_json_safe(path):
    """Lê JSON ignorando o BOM (Byte Order Mark) do Windows"""
    if not os.path.exists(path):
        return None
    with open(path, 'r', encoding='utf-8-sig') as f:
        return json.load(f)

def run_script(script_info):
    """Executa o script baseado no tipo (PowerShell ou Python)"""
    script_path = os.path.join(REPO_DIR, script_info["path"])
    script_name = script_info["name"]
    
    print(f"[EXECUTANDO] {script_name}...")
    
    try:
        if script_info["type"] == "python":
            # Usa o executável do Python que está rodando esta engine
            subprocess.run([sys.executable, script_path], check=True)
        elif script_info["type"] == "powershell":
            subprocess.run([
                "powershell.exe", "-NoProfile", "-NonInteractive", 
                "-ExecutionPolicy", "Bypass", "-File", script_path
            ], check=True)
        return True
    except Exception as e:
        print(f"[ERRO] Falha ao executar {script_name}: {e}")
        return False

def main():
    machine = load_json_safe(MACHINE_JSON)
    state = load_json_safe(STATE_JSON)
    manifest = load_json_safe(MANIFEST_JSON)

    if not machine or not manifest:
        print("[ERRO] Arquivos de configuração essenciais não encontrados.")
        return

    # Tag de identificação: "CLIENTE:SETOR"
    client_tag = f"{machine['cliente']}:{machine['setor']}"
    client_wildcard = f"{machine['cliente']}:*"

    for script in manifest.get("scripts", []):
        targets = script.get("targets", [])
        
        # Regra de Alvo: Se for global (*), se for o cliente:setor ou cliente:*
        is_target = "*" in targets or client_tag in targets or client_wildcard in targets
        
        if is_target:
            last_version = state["scripts"].get(script["name"])
            
            # Só roda se a versão for diferente (Idempotência)
            if last_version != script["version"]:
                success = run_script(script)
                if success:
                    state["scripts"][script["name"]] = script["version"]

    # Salva o novo estado
    with open(STATE_JSON, 'w', encoding='utf-8') as f:
        json.dump(state, f, indent=4)

if __name__ == "__main__":
    main()
