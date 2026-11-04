#!/usr/bin/env bash
# Redefine a senha de um admin direto no banco do cluster (para quando ninguem consegue logar).
# A senha e digitada aqui, vira hash BCrypt na sua maquina e so o hash vai para o banco.
# Uso: bash redefinir-senha-admin.sh admin@petservices.dev
set -euo pipefail

EMAIL="${1:?Uso: bash redefinir-senha-admin.sh email-do-admin}"
[[ "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$ ]] || { echo "E-mail invalido: $EMAIL"; exit 1; }

# a mesma biblioteca que o petServices usa para conferir a senha no login
JAR=$(ls ~/.m2/repository/org/springframework/security/spring-security-crypto/*/spring-security-crypto-*.jar 2>/dev/null | grep -v sources | sort -V | tail -1)
[ -n "$JAR" ] || { echo "spring-security-crypto nao encontrado no ~/.m2 (rode ./mvnw package no PetServices uma vez)"; exit 1; }

PSQL=(kubectl exec -i -n infra postgres-0 -- psql -U postgres -d cadastros_db -v ON_ERROR_STOP=1 -tA)
EXISTE=$("${PSQL[@]}" -c "select count(*) from tb_admin where email = '$EMAIL'")
if [ "$EXISTE" != "1" ]; then
    echo "Nenhum admin com o e-mail $EMAIL. Admins cadastrados:"
    "${PSQL[@]}" -c "select email from tb_admin order by id"
    exit 1
fi

read -rsp "Nova senha (minimo 12 caracteres): " SENHA; echo
read -rsp "Repita a nova senha: " CONFIRMA; echo
[ "$SENHA" = "$CONFIRMA" ] || { echo "As senhas nao conferem. Nada foi alterado."; exit 1; }
[ ${#SENHA} -ge 12 ] || { echo "A senha precisa ter pelo menos 12 caracteres. Nada foi alterado."; exit 1; }

# a senha vai pela entrada padrao (nao aparece no ps nem no historico do shell)
GERADOR=$(mktemp -d)
trap 'rm -rf "$GERADOR"' EXIT
cat > "$GERADOR/Hash.java" <<'JAVA'
import org.springframework.security.crypto.bcrypt.BCrypt;
public class Hash {
    public static void main(String[] args) throws Exception {
        String senha = new String(System.in.readAllBytes(), "UTF-8");
        System.out.print(BCrypt.hashpw(senha, BCrypt.gensalt(10)));
    }
}
JAVA
HASH=$(printf '%s' "$SENHA" | java -cp "$JAR" "$GERADOR/Hash.java")
unset SENHA CONFIRMA
[[ "$HASH" =~ ^\$2a\$10\$[./A-Za-z0-9]{53}$ ]] || { echo "Falha ao gerar o hash. Nada foi alterado."; exit 1; }

RESULTADO=$(printf "update tb_admin set senha = '%s' where email = '%s';\n" "$HASH" "$EMAIL" | "${PSQL[@]}")
echo "$RESULTADO"
[ "$RESULTADO" = "UPDATE 1" ] && echo "Senha de $EMAIL redefinida. Ja pode fazer login."
