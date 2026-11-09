-- ============================================================
-- PROJETO HITECH | BANCO DE DADOS RELACIONAL
-- SGBD: MySQL 8.0
-- Arquivo consolidado: estrutura, regras, dados e consultas.
--
-- ATENCAO:
-- 1) Para gerar um DER em um site de diagramas, use somente a
--    PARTE 1 (CREATE DATABASE / CREATE TABLE / INDEXES).
-- 2) A PARTE 4 contem testes que devem ser executados um a um.
--    Os testes negativos foram deixados comentados porque devem
--    produzir erros de validacao.
-- 3) Este script cria o banco do zero. Se ja houver tabelas com
--    esses nomes, faça backup antes de executar.
-- ============================================================

CREATE DATABASE IF NOT EXISTS hitech_erp;
USE hitech_erp;

-- ============================================================
-- PARTE 1 - ESTRUTURA DO BANCO E DAS TABELAS
-- ============================================================

CREATE TABLE cliente (
    id_cliente INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(120) NOT NULL,
    email VARCHAR(120) UNIQUE,
    telefone VARCHAR(20),
    data_cadastro DATE NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE nivel_profissional (
    id_nivel INT AUTO_INCREMENT PRIMARY KEY,
    nome_nivel VARCHAR(20) NOT NULL UNIQUE,
    descricao VARCHAR(200),
    complexidade_permitida VARCHAR(20) NOT NULL,
    CONSTRAINT chk_nivel_nome
        CHECK (nome_nivel IN ('Junior', 'Pleno', 'Senior')),
    CONSTRAINT chk_nivel_complexidade
        CHECK (complexidade_permitida IN ('Simples', 'Media', 'Alta'))
);

CREATE TABLE funcionario (
    id_funcionario INT AUTO_INCREMENT PRIMARY KEY,
    id_nivel INT NOT NULL,
    nome VARCHAR(120) NOT NULL,
    email VARCHAR(120) NOT NULL UNIQUE,
    data_admissao DATE NOT NULL,
    ativo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT fk_funcionario_nivel
        FOREIGN KEY (id_nivel)
        REFERENCES nivel_profissional(id_nivel)
        ON UPDATE CASCADE
        ON DELETE RESTRICT
);

CREATE TABLE projeto (
    id_projeto INT AUTO_INCREMENT PRIMARY KEY,
    id_cliente INT NOT NULL,
    nome_projeto VARCHAR(150) NOT NULL,
    descricao TEXT,
    data_inicio DATE NOT NULL,
    data_prevista_fim DATE,
    data_conclusao DATE,
    status VARCHAR(20) NOT NULL DEFAULT 'Planejado',
    CONSTRAINT fk_projeto_cliente
        FOREIGN KEY (id_cliente)
        REFERENCES cliente(id_cliente)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT chk_projeto_status
        CHECK (status IN ('Planejado', 'Em andamento', 'Concluido', 'Cancelado')),
    CONSTRAINT chk_projeto_datas
        CHECK (data_prevista_fim IS NULL OR data_prevista_fim >= data_inicio)
);

CREATE TABLE tarefa (
    id_tarefa INT AUTO_INCREMENT PRIMARY KEY,
    id_projeto INT NOT NULL,
    titulo VARCHAR(150) NOT NULL,
    descricao TEXT,
    complexidade VARCHAR(20) NOT NULL,
    status VARCHAR(20) NOT NULL DEFAULT 'Pendente',
    data_criacao DATE NOT NULL,
    data_prazo DATE,
    data_conclusao DATE,
    CONSTRAINT fk_tarefa_projeto
        FOREIGN KEY (id_projeto)
        REFERENCES projeto(id_projeto)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT chk_tarefa_complexidade
        CHECK (complexidade IN ('Simples', 'Media', 'Alta')),
    CONSTRAINT chk_tarefa_status
        CHECK (status IN ('Pendente', 'Em andamento', 'Concluida', 'Bloqueada', 'Cancelada'))
);

CREATE TABLE alocacao_tarefa (
    id_alocacao INT AUTO_INCREMENT PRIMARY KEY,
    id_tarefa INT NOT NULL,
    id_funcionario INT NOT NULL,
    data_inicio DATE NOT NULL,
    data_fim DATE,
    CONSTRAINT fk_alocacao_tarefa
        FOREIGN KEY (id_tarefa)
        REFERENCES tarefa(id_tarefa)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_alocacao_funcionario
        FOREIGN KEY (id_funcionario)
        REFERENCES funcionario(id_funcionario)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT chk_alocacao_datas
        CHECK (data_fim IS NULL OR data_fim >= data_inicio)
);

CREATE TABLE historico_tarefa (
    id_historico INT AUTO_INCREMENT PRIMARY KEY,
    id_tarefa INT NOT NULL,
    id_funcionario INT,
    status_anterior VARCHAR(20),
    status_novo VARCHAR(20) NOT NULL,
    data_alteracao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    observacao VARCHAR(500),
    CONSTRAINT fk_historico_tarefa
        FOREIGN KEY (id_tarefa)
        REFERENCES tarefa(id_tarefa)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT fk_historico_funcionario
        FOREIGN KEY (id_funcionario)
        REFERENCES funcionario(id_funcionario)
        ON UPDATE CASCADE
        ON DELETE RESTRICT,
    CONSTRAINT chk_historico_status_novo
        CHECK (status_novo IN ('Pendente', 'Em andamento', 'Concluida', 'Bloqueada', 'Cancelada')),
    CONSTRAINT chk_historico_status_anterior
        CHECK (
            status_anterior IS NULL OR
            status_anterior IN ('Pendente', 'Em andamento', 'Concluida', 'Bloqueada', 'Cancelada')
        )
);

CREATE INDEX idx_projeto_cliente ON projeto(id_cliente);
CREATE INDEX idx_tarefa_projeto ON tarefa(id_projeto);
CREATE INDEX idx_tarefa_status ON tarefa(status);
CREATE INDEX idx_alocacao_funcionario ON alocacao_tarefa(id_funcionario);
CREATE INDEX idx_historico_tarefa ON historico_tarefa(id_tarefa);

-- ============================================================
-- PARTE 2 - TRIGGERS DE VALIDACAO
-- Junior = Simples | Pleno = Media | Senior = Alta
-- Uma tarefa pode ter apenas uma alocacao ativa por vez.
-- ============================================================

DELIMITER $$

CREATE TRIGGER trg_validar_alocacao_insert
BEFORE INSERT ON alocacao_tarefa
FOR EACH ROW
BEGIN
    DECLARE v_complexidade VARCHAR(20);
    DECLARE v_complexidade_permitida VARCHAR(20);
    DECLARE v_ativo INT;

    SELECT t.complexidade INTO v_complexidade
    FROM tarefa t
    WHERE t.id_tarefa = NEW.id_tarefa;

    SELECT n.complexidade_permitida INTO v_complexidade_permitida
    FROM funcionario f
    INNER JOIN nivel_profissional n ON n.id_nivel = f.id_nivel
    WHERE f.id_funcionario = NEW.id_funcionario
      AND f.ativo = TRUE;

    IF v_complexidade_permitida IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Funcionario inexistente ou inativo.';
    END IF;

    IF v_complexidade <> v_complexidade_permitida THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nivel profissional incompativel com a tarefa.';
    END IF;

    SELECT COUNT(*) INTO v_ativo
    FROM alocacao_tarefa
    WHERE id_tarefa = NEW.id_tarefa
      AND data_fim IS NULL;

    IF v_ativo > 0 AND NEW.data_fim IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A tarefa ja possui uma alocacao ativa.';
    END IF;
END$$

CREATE TRIGGER trg_validar_alocacao_update
BEFORE UPDATE ON alocacao_tarefa
FOR EACH ROW
BEGIN
    DECLARE v_complexidade VARCHAR(20);
    DECLARE v_complexidade_permitida VARCHAR(20);
    DECLARE v_ativo INT;

    SELECT t.complexidade INTO v_complexidade
    FROM tarefa t
    WHERE t.id_tarefa = NEW.id_tarefa;

    SELECT n.complexidade_permitida INTO v_complexidade_permitida
    FROM funcionario f
    INNER JOIN nivel_profissional n ON n.id_nivel = f.id_nivel
    WHERE f.id_funcionario = NEW.id_funcionario
      AND f.ativo = TRUE;

    IF v_complexidade_permitida IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Funcionario inexistente ou inativo.';
    END IF;

    IF v_complexidade <> v_complexidade_permitida THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Nivel profissional incompativel com a tarefa.';
    END IF;

    SELECT COUNT(*) INTO v_ativo
    FROM alocacao_tarefa
    WHERE id_tarefa = NEW.id_tarefa
      AND data_fim IS NULL
      AND id_alocacao <> OLD.id_alocacao;

    IF v_ativo > 0 AND NEW.data_fim IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'A tarefa ja possui outra alocacao ativa.';
    END IF;
END$$

DELIMITER ;

-- ============================================================
-- PARTE 3 - MASSA DE DADOS FICTICIOS
-- ============================================================

INSERT INTO nivel_profissional
(nome_nivel, descricao, complexidade_permitida)
VALUES
('Junior', 'Desenvolvedor em inicio de carreira', 'Simples'),
('Pleno', 'Desenvolvedor com experiencia intermediaria', 'Media'),
('Senior', 'Desenvolvedor com experiencia avancada', 'Alta');

INSERT INTO cliente (nome, email, telefone, data_cadastro)
VALUES
('Comercial Alfa', 'contato@alfa.com', '11999990001', '2026-01-10'),
('Grupo Beta', 'contato@beta.com', '11999990002', '2026-01-15'),
('Empresa Gamma', 'contato@gamma.com', '11999990003', '2026-02-01');

INSERT INTO funcionario (id_nivel, nome, email, data_admissao)
VALUES
(1, 'Lucas Martins', 'lucas@hitech.com', '2025-03-10'),
(1, 'Pedro Alves', 'pedro@hitech.com', '2025-06-15'),
(2, 'Mariana Costa', 'mariana@hitech.com', '2024-02-20'),
(2, 'Rafael Lima', 'rafael@hitech.com', '2024-05-12'),
(3, 'Fernanda Souza', 'fernanda@hitech.com', '2022-08-01'),
(3, 'Gabriel Rocha', 'gabriel@hitech.com', '2021-11-18');

INSERT INTO projeto
(id_cliente, nome_projeto, descricao, data_inicio, data_prevista_fim, status)
VALUES
(1, 'Sistema de Vendas', 'Sistema para controle de vendas comerciais.', '2026-02-01', '2026-06-30', 'Em andamento'),
(2, 'Sistema Financeiro', 'Sistema para controle financeiro empresarial.', '2026-02-15', '2026-07-15', 'Em andamento'),
(3, 'Sistema de Estoque', 'Sistema para gerenciamento de estoque.', '2026-03-01', '2026-08-30', 'Planejado');

INSERT INTO tarefa
(id_projeto, titulo, descricao, complexidade, status, data_criacao, data_prazo)
VALUES
(1, 'Criar tela de cadastro', 'Implementar cadastro basico de produtos.', 'Simples', 'Em andamento', '2026-02-02', '2026-03-15'),
(1, 'Criar modulo de relatorios', 'Desenvolver consultas e relatorios de vendas.', 'Media', 'Pendente', '2026-02-03', '2026-04-10'),
(1, 'Desenvolver arquitetura', 'Definir arquitetura principal do sistema.', 'Alta', 'Em andamento', '2026-02-04', '2026-05-10'),
(2, 'Criar cadastro financeiro', 'Implementar cadastro de contas.', 'Simples', 'Pendente', '2026-02-16', '2026-03-20'),
(2, 'Desenvolver fluxo financeiro', 'Implementar fluxo de movimentacoes.', 'Media', 'Em andamento', '2026-02-17', '2026-05-20'),
(3, 'Definir arquitetura de estoque', 'Projetar estrutura geral do sistema.', 'Alta', 'Pendente', '2026-03-02', '2026-06-10');

INSERT INTO alocacao_tarefa (id_tarefa, id_funcionario, data_inicio)
VALUES
(1, 1, '2026-02-05'),
(2, 3, '2026-02-10'),
(3, 5, '2026-02-12'),
(4, 2, '2026-02-20'),
(5, 4, '2026-02-21'),
(6, 6, '2026-03-05');

INSERT INTO historico_tarefa
(id_tarefa, id_funcionario, status_anterior, status_novo, observacao)
VALUES
(1, 1, 'Pendente', 'Em andamento', 'Inicio do desenvolvimento.'),
(2, 3, NULL, 'Pendente', 'Tarefa cadastrada.'),
(3, 5, 'Pendente', 'Em andamento', 'Inicio da arquitetura.'),
(4, 2, NULL, 'Pendente', 'Tarefa cadastrada.'),
(5, 4, 'Pendente', 'Em andamento', 'Inicio da implementacao.'),
(6, 6, NULL, 'Pendente', 'Tarefa cadastrada.');

-- ============================================================
-- PARTE 4 - TESTES DE VALIDACAO
-- Execute os testes negativos individualmente, descomentando
-- um por vez. O resultado esperado e a rejeicao da operacao.
-- ============================================================

-- TESTE PK: deve falhar por ID duplicado.
-- INSERT INTO cliente (id_cliente, nome, data_cadastro)
-- VALUES (1, 'Cliente Duplicado', '2026-03-10');

-- TESTE FK: deve falhar porque o cliente 999 nao existe.
-- INSERT INTO projeto (id_cliente, nome_projeto, data_inicio, status)
-- VALUES (999, 'Projeto Invalido', '2026-03-10', 'Planejado');

-- TESTE NOT NULL: deve falhar porque nome e obrigatorio.
-- INSERT INTO cliente (nome, data_cadastro)
-- VALUES (NULL, '2026-03-10');

-- TESTE COMPLEXIDADE: deve falhar (tarefa 3 = Alta; funcionario 1 = Junior).
-- INSERT INTO alocacao_tarefa (id_tarefa, id_funcionario, data_inicio)
-- VALUES (3, 1, '2026-03-10');

-- TESTE ALOCACAO DUPLICADA: deve falhar (tarefa 1 ja tem alocacao ativa).
-- INSERT INTO alocacao_tarefa (id_tarefa, id_funcionario, data_inicio)
-- VALUES (1, 2, '2026-03-10');

-- TESTE JOIN: combina tarefa, projeto, cliente e responsavel atual.
SELECT
    t.id_tarefa, t.titulo, t.complexidade, t.status,
    p.nome_projeto, c.nome AS cliente,
    f.nome AS funcionario, n.nome_nivel
FROM tarefa t
INNER JOIN projeto p ON p.id_projeto = t.id_projeto
INNER JOIN cliente c ON c.id_cliente = p.id_cliente
LEFT JOIN alocacao_tarefa a
    ON a.id_tarefa = t.id_tarefa AND a.data_fim IS NULL
LEFT JOIN funcionario f ON f.id_funcionario = a.id_funcionario
LEFT JOIN nivel_profissional n ON n.id_nivel = f.id_nivel;

-- TESTE UPDATE: atualiza uma tarefa especifica.
-- Descomente para executar em ambiente de teste.
-- UPDATE tarefa
-- SET status = 'Concluida', data_conclusao = '2026-03-20'
-- WHERE id_tarefa = 1;
-- SELECT * FROM tarefa WHERE id_tarefa = 1;

-- TESTE DELETE: cria e remove um cliente temporario.
-- Descomente para executar em ambiente de teste.
-- INSERT INTO cliente (nome, email, telefone, data_cadastro)
-- VALUES ('Cliente Temporario', 'temporario@exemplo.com', '11988887777', '2026-03-10');
-- DELETE FROM cliente WHERE email = 'temporario@exemplo.com';

-- ============================================================
-- PARTE 5 - CONSULTAS GERENCIAIS E DE AUDITORIA
-- ============================================================

-- 5.1 Projetos e respectivos clientes.
SELECT
    p.id_projeto, p.nome_projeto, c.nome AS cliente,
    p.status, p.data_inicio, p.data_prevista_fim
FROM projeto p
INNER JOIN cliente c ON c.id_cliente = p.id_cliente
ORDER BY p.data_inicio;

-- 5.2 Tarefas atualmente atribuidas por funcionario.
SELECT
    f.nome AS funcionario, n.nome_nivel,
    t.titulo AS tarefa, t.complexidade, t.status
FROM alocacao_tarefa a
INNER JOIN funcionario f ON f.id_funcionario = a.id_funcionario
INNER JOIN nivel_profissional n ON n.id_nivel = f.id_nivel
INNER JOIN tarefa t ON t.id_tarefa = a.id_tarefa
WHERE a.data_fim IS NULL
ORDER BY f.nome;

-- 5.3 Quantidade de tarefas por situacao.
SELECT status, COUNT(*) AS quantidade
FROM tarefa
GROUP BY status;

-- 5.4 Tarefas atrasadas e ainda nao concluidas/canceladas.
SELECT
    t.id_tarefa, t.titulo, t.data_prazo, t.status, p.nome_projeto
FROM tarefa t
INNER JOIN projeto p ON p.id_projeto = t.id_projeto
WHERE t.data_prazo < CURRENT_DATE
  AND t.status NOT IN ('Concluida', 'Cancelada')
ORDER BY t.data_prazo;

-- 5.5 Quantidade historica de atribuicoes por funcionario.
SELECT
    f.id_funcionario, f.nome, n.nome_nivel,
    COUNT(a.id_alocacao) AS total_atribuicoes
FROM funcionario f
INNER JOIN nivel_profissional n ON n.id_nivel = f.id_nivel
LEFT JOIN alocacao_tarefa a ON a.id_funcionario = f.id_funcionario
GROUP BY f.id_funcionario, f.nome, n.nome_nivel
ORDER BY total_atribuicoes DESC;

-- 5.6 Historico de uma tarefa (exemplo: tarefa 1).
SELECT
    h.id_historico, t.titulo, h.status_anterior, h.status_novo,
    h.data_alteracao, f.nome AS responsavel_pelo_registro, h.observacao
FROM historico_tarefa h
INNER JOIN tarefa t ON t.id_tarefa = h.id_tarefa
LEFT JOIN funcionario f ON f.id_funcionario = h.id_funcionario
WHERE h.id_tarefa = 1
ORDER BY h.data_alteracao;

-- FIM DO SCRIPT HITECH
