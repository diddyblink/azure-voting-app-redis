#!/bin/bash
set -e

# --- INPUT UTENTE ---
read -p "Inserisci il project: " PROJECT
read -p "Inserisci il nome della origin pvc: " ORIGIN_PVC_NAME

# Calcolo nome PVC temporanea
TEMP_PVC_NAME="${ORIGIN_PVC_NAME}-migrate-temp"

echo "--------------------------------------------------"
echo "Analisi risorse in corso nel project '$PROJECT'..."

# 1. CHECK & RECUPERO DATI
# Verifichiamo la presenza della temp
if ! oc get pvc "$TEMP_PVC_NAME" -n "$PROJECT" > /dev/null 2>&1; then
    echo "ERRORE: La PVC temporanea '$TEMP_PVC_NAME' non esiste."
    exit 1
fi

# Recupero dati dal NUOVO volume (quello su cui abbiamo migrato i dati)
NEW_PV=$(oc get pvc ${TEMP_PVC_NAME} -n ${PROJECT} -o jsonpath='{.spec.volumeName}')
DETECTED_SC=$(oc get pvc ${TEMP_PVC_NAME} -n ${PROJECT} -o jsonpath='{.spec.storageClassName}')

# Recupero dati dalla VECCHIA PVC (per clonarla identica)
ORIGIN_SIZE=$(oc get pvc "$ORIGIN_PVC_NAME" -n "$PROJECT" -o jsonpath='{.spec.resources.requests.storage}')
ORIGIN_MODE=$(oc get pvc "$ORIGIN_PVC_NAME" -n "$PROJECT" -o jsonpath='{.spec.accessModes[0]}')

# Recupero labels formattate per YAML
ORIGIN_LABELS_YAML=$(oc get pvc "$ORIGIN_PVC_NAME" -n "$PROJECT" -o go-template='{{range $k,$v := .metadata.labels}}    {{$k}}: "{{$v}}"{{"\n"}}{{end}}')

if [ -z "$NEW_PV" ]; then
  echo "ERRORE: PV non trovato sulla temp pvc."
  exit 1
fi

echo "Dati Recuperati:"
echo " - Volume Target (V2):   $NEW_PV"
echo " - StorageClass Target:  $DETECTED_SC"
echo " - Config da clonare:    $ORIGIN_SIZE / $ORIGIN_MODE"
echo "--------------------------------------------------"
echo "Inizio Fase 2: Swap del Volume..."

# 2. CHECK APPLICAZIONE (Solo controllo)
echo "Controllo che i Pod siano spenti..."
POD_COUNT=$(oc get pods -n "$PROJECT" --no-headers | grep -v "migration-job" | wc -l)
if [ "$POD_COUNT" -gt "0" ]; then
    echo "ATTENZIONE: Ci sono ancora Pod attivi. Assicurati di aver fatto 'oc scale --replicas=0 ...'"
    read -p "Premi INVIO per confermare che l'app è spenta e procedere..."
fi

# 3. ELIMINAZIONE PVC TEMPORANEA
echo "--- Eliminazione PVC Temporanea (Il PV $NEW_PV andrà in stato 'Released')..."
# Rimuoviamo finalizer per sicurezza e cancelliamo
oc patch pvc ${TEMP_PVC_NAME} -n ${PROJECT} -p '{"metadata":{"finalizers":null}}' --type=merge || true
oc delete pvc ${TEMP_PVC_NAME} -n ${PROJECT} --wait=true --ignore-not-found

# 4. SWAP PVC UFFICIALE
echo "--- Eliminazione Vecchia PVC Ufficiale..."
oc patch pvc ${ORIGIN_PVC_NAME} -n ${PROJECT} -p '{"metadata":{"finalizers":null}}' --type=merge || true
oc delete pvc ${ORIGIN_PVC_NAME} -n ${PROJECT} --wait=true --ignore-not-found

# 5. CREAZIONE NUOVA PVC (Strategia "Lock-First")
# Creiamo la PVC *prima* di sbloccare il PV. 
# Grazie a 'volumeName', questa PVC reclamerà esplicitamente il PV $NEW_PV.
echo "--- Creazione Nuova PVC Ufficiale (Linkata a $NEW_PV)..."
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${ORIGIN_PVC_NAME}
  namespace: ${PROJECT}
  labels:
${ORIGIN_LABELS_YAML}
spec:
  accessModes:
    - ${ORIGIN_MODE}
  resources:
    requests:
      storage: ${ORIGIN_SIZE}
  storageClassName: ${DETECTED_SC}
  volumeName: ${NEW_PV}              
EOF

# 6. SBLOCCO DEL PV
# Ora che la PVC esiste ed è in attesa di *quel* volume, rimuoviamo il claimRef.
# Kubernetes vedrà il PV libero e lo legherà immediatamente alla PVC che lo sta chiamando per nome.
echo "--- Sblocco del PV (Rimozione ClaimRef vecchio)..."
oc patch pv ${NEW_PV} --type json -p='[{"op": "remove", "path": "/spec/claimRef"}]' || true

# 7. VERIFICA FINALE
echo "--- Attesa Binding..."
oc wait --for=jsonpath='{.status.phase}'=Bound pvc/${ORIGIN_PVC_NAME} -n ${PROJECT} --timeout=60s

echo ""
echo "FASE 2 COMPLETATA!"
echo "Il volume $NEW_PV è ora bound correttamente alla pvc ufficiale '$ORIGIN_PVC_NAME'."
echo "StorageClass: $DETECTED_SC | Size: $ORIGIN_SIZE"
echo ""
echo "PROSSIMI STEP:"
echo "1. Aggiorna i manifest Git con i nuovi valori (SC e volumeName)."
echo "2. Esegui lo SCALE UP manuale dell'applicazione."
