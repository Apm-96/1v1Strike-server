from fastapi import FastAPI, HTTPException
import subprocess
import random
# Commanda: sudo python3 -m uvicorn Controller:app --host 0.0.0.0 --port 5000
app = FastAPI()

SERVIDORS = {
    "queen": {"service": "xash-queen", "url": "http://192.168.1.114:27016"},
    "crete": {"service": "xash-crete", "url": "http://192.168.1.114:27018"},
    "marc":  {"service": "xash-marc",  "url": "http://192.168.1.114:27020"}
}

def esta_corrent(service_name):
    """Comprova si el contenidor ja està en marxa"""
    # Busquem el nom exacte per evitar falsos positius
    result = subprocess.run(
        ["sudo", "docker", "ps", "--filter", f"name={service_name}", "--format", "{{.Names}}"],
        capture_output=True, text=True
    )
    # Docker ps amb filtre de nom pot retornar sub-strings, 
    # verifiquem que el nom del servei estigui a la llista
    return any(service_name in line for line in result.stdout.split('\n'))

@app.post("/partida-aleatoria")
async def partida_aleatoria():
    # 1. Busquem quins servidors NO estan corrent
    lliures = []
    for nom, info in SERVIDORS.items():
        if not esta_corrent(info["service"]):
            lliures.append(nom)
    
    # 2. Si no hi ha cap servidor lliure
    if not lliures:
        raise HTTPException(
            status_code=503, 
            detail="Tots els servidors estan ocupats. Espera que acabi alguna partida."
        )

    # 3. Triem un dels lliures a l'atzar
    triat = random.choice(lliures)
    info = SERVIDORS[triat]

    # 4. L'aixequem
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
        
        # Aturem el servei. Docker no el reiniciarà tot i el 'restart: always'
        # perquè és una parada explícita.
        subprocess.run(["sudo", "docker", "compose", "stop", servei])
        
        return {"status": "success", "message": f"{servei} aturat"}
    
    return {"status": "error", "message": "Servidor no reconegut"}
