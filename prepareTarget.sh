#!/bin/bash
set -e # Esce se c'è un errore

# --- INPUT UTENTE ---
read -p "Inserisci il project: " PROJECT
read -p "Inserisci il nome della origin pvc: " ORIGIN_PVC_NAME
read -p "Inserisci il nome della sc target: " TARGET_SC

# --- RECUPERO DATI DINAMICI ---
echo "--- Analisi della PVC Originale: $ORIGIN_PVC_NAME ---"

# 1. Generazione Nome Temp
TEMP_PVC_NAME="${ORIGIN_PVC_NAME}-migrate-temp"

# 2. Recupero Size
SIZE=$(oc get pvc "$ORIGIN_PVC_NAME" -n "$PROJECT" -o jsonpath='{.spec.resources.requests.storage}')

# 3. Recupero Access Mode
ACCESS_MODE=$(oc get pvc "$ORIGIN_PVC_NAME" -n "$PROJECT" -o jsonpath='{.spec.accessModes[0]}')

# 4. RECUPERO LABELS (La Magia)
# Questo comando estrae le label e le formatta già come YAML: "    chiave: valore"
LABELS_YAML=$(oc get pvc "$ORIGIN_PVC_NAME" -n "$PROJECT" -o go-template='{{range $k,$v := .metadata.labels}}    {{$k}}: "{{$v}}"{{"\n"}}{{end}}')

echo "-------------------------------------"
echo "Configurazione Rilevata:"
echo "Temp Name:   $TEMP_PVC_NAME"
echo "Target SC:   $TARGET_SC"
echo "Size:        $SIZE"
echo "Labels:"
echo "$LABELS_YAML" | sed 's/^/  /' # Solo per visualizzazione a schermo
echo "-------------------------------------"

# --- CREAZIONE PVC TEMPORANEA ---
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${TEMP_PVC_NAME}
  namespace: ${PROJECT}
  labels:
    # Label nostre di servizio per capire che è una migrazione
    migration-temp: "true"
    source-pvc: "${ORIGIN_PVC_NAME}"
    # Qui iniettiamo le label originali, già indentate correttamente
${LABELS_YAML}
spec:
  storageClassName: "${TARGET_SC}"
  accessModes:
    - ${ACCESS_MODE}
  resources:
    requests:
      storage: ${SIZE}
EOF

# 2. Attesa Binding
echo "--- Attesa che il volume sia Bound..."
oc wait --for=jsonpath='{.status.phase}'=Bound pvc/${TEMP_PVC_NAME} -n ${PROJECT} --timeout=60s

# 3. Estrazione Nome PV
NEW_PV=$(oc get pvc ${TEMP_PVC_NAME} -n ${PROJECT} -o jsonpath='{.spec.volumeName}')
echo "Volume creato: ${NEW_PV}"

# 4. Patch Retain 
echo "--- Impostazione Policy 'Retain' sul PV..."
oc patch pv ${NEW_PV} -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'

echo ""
echo "FASE 1 COMPLETATA!"
echo "Il nuovo volume fisico è: ${NEW_PV}"
echo "ORA ESEGUI LA MIGRAZIONE DATI SUL VOLUME LEGATO A '${TEMP_PVC_NAME}'"
echo "Quando i dati sono copiati, lancia lo script 2."
