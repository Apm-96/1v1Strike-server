from fastapi import FastAPI, HTTPException
import subprocess
import random
import requests
import os
# Commanda: python3 -m uvicorn Controller:app --host 0.0.0.0 --port 5000
app = FastAPI()
#SERVER_IP = os.getenv('SERVER_IP', '127.0.0.1')
SERVIDORS = {
    "queen": {"service": "xash-queen", "url": "http://strike1v1-match.duckdns.org:1128"},
    "crete": {"service": "xash-crete", "url": "http://strike1v1-match.duckdns.org:1130"},
    "marc":  {"service": "xash-marc",  "url": "http://strike1v1-match.duckdns.org:1132"}
}

def esta_corrent(service_name):
    """Comprova si el contenidor ja està en marxa"""
    # Busca el nom exacte per evitar falsos positius
    result = subprocess.run(
        ["sudo", "docker", "ps", "--filter", f"name={service_name}", "--format", "{{.Names}}"],
        capture_output=True, text=True
    )
    # Docker ps amb filtre de nom pot retornar sub-strings, verifiquem que el nom del servei estigui a la llista
    return any(service_name in line for line in result.stdout.split('\n'))

@app.post("/partida-aleatoria")
async def partida_aleatoria():
    # Busca quins servidors NO estan corrent
    lliures = []
    for nom, info in SERVIDORS.items():
        if not esta_corrent(info["service"]):
            lliures.append(nom)
    
    if not lliures:
        raise HTTPException(
            status_code=503, 
            detail="Tots els servidors estan ocupats. Espera que acabi alguna partida."
        )

    # Tria un dels lliures a l'atzar
    triat = random.choice(lliures)
    info = SERVIDORS[triat]

    # L'aixeca
    try:
        # Check=True farà que si Docker falla, vagi directament a l'except
        subprocess.run(["sudo", "docker", "compose", "up", "-d", info["service"]], check=True)
        return {
            "status": "success",
            "mapa": triat,
            "url": info["url"]
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error en aixecar Docker: {str(e)}")

@app.post("/tancar-tots")
async def tancar_tots():
    subprocess.run(["sudo", "docker", "compose", "stop"])
    return {"message": "Tots els servidors s'han aturat"}

@app.post("/detenir-servidor/{nom}")
async def detenir_servidor(nom: str):
    # 'nom' serà 'marc', 'crete' o 'queen'
    if nom in SERVIDORS:
        servei = SERVIDORS[nom]["service"]
        print(f"--- Rebut senyal de tancament per a: {servei} ---")
        
        # Atura el servei. Docker no el reiniciarà tot i el 'restart: always' perquè és una parada explícita.
        subprocess.run(["sudo", "docker", "compose", "stop", servei])
        
        return {"status": "success", "message": f"{servei} aturat"}
    
    return {"status": "error", "message": "Servidor no reconegut"}

@app.post("/registrar-partida")
async def registrar_partida(data: dict):
    # Reenviem la informació a Django
    # Django sol estar al port 8000
    django_url = f"http://strike1v1.duckdns.org:1136/save-match" # O la IP que usis
    
    try:
        response = requests.post(django_url, json=data, timeout=5)
        return {"status": "forwarded", "django_response": response.status_code}
    except Exception as e:
        return {"status": "error", "message": str(e)}
