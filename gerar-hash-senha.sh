#!/usr/bin/env bash
# Gera o hash BCrypt de uma senha, no mesmo formato que o petServices confere no login.
# Use o resultado na coluna "senha" ao inserir um usuario direto no banco.
# Uso: bash gerar-hash-senha.sh
set -euo pipefail

JAR=$(ls ~/.m2/repository/org/springframework/security/spring-security-crypto/*/spring-security-crypto-*.jar 2>/dev/null | grep -v sources | sort -V | tail -1)
[ -n "$JAR" ] || { echo "spring-security-crypto nao encontrado no ~/.m2 (rode ./mvnw package no PetServices uma vez)"; exit 1; }

read -rsp "Senha (minimo 12 caracteres): " SENHA; echo
read -rsp "Repita a senha: " CONFIRMA; echo
[ "$SENHA" = "$CONFIRMA" ] || { echo "As senhas nao conferem."; exit 1; }
[ ${#SENHA} -ge 12 ] || { echo "A senha precisa ter pelo menos 12 caracteres."; exit 1; }

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
# a senha vai pela entrada padrao (nao aparece no ps nem no historico do shell)
printf '%s' "$SENHA" | java -cp "$JAR" "$GERADOR/Hash.java"
echo
