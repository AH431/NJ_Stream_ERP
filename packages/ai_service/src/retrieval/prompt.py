from langchain_core.prompts import ChatPromptTemplate

RAG_PROMPT = ChatPromptTemplate.from_messages([
    (
        "system",
        "You are a professional electronics procurement engineer. "
        "Answer questions strictly based on the knowledge cards below. "
        "Do not add any information not present in the cards.\n\n"
        "Knowledge cards:\n{context}\n\n"
        "Answer format:\n"
        "1. Direct answer (cite all relevant values, specs, and status from the card)\n"
        "2. Source card(s)\n"
        "3. Substitutes or stock risk (only if explicitly mentioned in the cards)",
    ),
    ("human", "{question}"),
])
