// Provider tests - basic smoke tests for provider initialization and structure
// Full integration tests require actual API keys or running mock servers

use thanos::types::{ChatMessage, ChatRequest, Role};

/// Helper to create a test chat request
fn create_test_request() -> ChatRequest {
    ChatRequest {
        model: "test-model".to_string(),
        messages: vec![ChatMessage {
            role: Role::User,
            content: "Hello".to_string(),
        }],
        stream: false,
        temperature: Some(0.7),
        max_tokens: Some(100),
        top_p: None,
        system: None,
    }
}

#[cfg(test)]
mod provider_initialization_tests {
    
    use thanos::providers::*;

    #[test]
    fn test_anthropic_provider_creation() {
        let provider = anthropic::AnthropicProvider::new(
            "test-api-key".to_string(),
            "claude-sonnet-4-5".to_string(),
        );
        // Provider should be created successfully
        assert!(std::mem::size_of_val(&provider) > 0);
    }

    #[test]
    fn test_openai_provider_creation() {
        let provider = openai::OpenAIProvider::new(
            "test-api-key".to_string(),
            "gpt-4o".to_string(),
        );
        assert!(std::mem::size_of_val(&provider) > 0);
    }

    #[test]
    fn test_gemini_provider_creation() {
        let provider = gemini::GeminiProvider::new(
            "test-api-key".to_string(),
            "gemini-2.5-pro".to_string(),
        );
        assert!(std::mem::size_of_val(&provider) > 0);
    }

    #[test]
    fn test_xai_provider_creation() {
        let provider = xai::XAIProvider::new(
            "test-api-key".to_string(),
            "grok-2-latest".to_string(),
        );
        assert!(std::mem::size_of_val(&provider) > 0);
    }

    #[test]
    fn test_ollama_provider_creation() {
        let provider = ollama::OllamaProvider::new(
            "http://localhost:11434".to_string(),
            "llama3.2".to_string(),
        );
        assert!(std::mem::size_of_val(&provider) > 0);
    }

    #[test]
    fn test_github_copilot_provider_creation() {
        let provider = github_copilot::GitHubCopilotProvider::new(
            "gpt-4o".to_string(),
        );
        assert!(std::mem::size_of_val(&provider) > 0);
    }
}

#[cfg(test)]
mod chat_request_tests {
    use super::*;

    #[test]
    fn test_chat_request_structure() {
        let request = create_test_request();

        assert_eq!(request.messages.len(), 1);
        assert_eq!(request.messages[0].role, Role::User);
        assert_eq!(request.messages[0].content, "Hello");
        assert_eq!(request.model, "test-model");
        assert_eq!(request.temperature, Some(0.7));
        assert_eq!(request.max_tokens, Some(100));
        assert!(!request.stream);
    }

    #[test]
    fn test_message_roles() {
        let user_msg = ChatMessage {
            role: Role::User,
            content: "User message".to_string(),
        };

        let assistant_msg = ChatMessage {
            role: Role::Assistant,
            content: "Assistant message".to_string(),
        };

        let system_msg = ChatMessage {
            role: Role::System,
            content: "System message".to_string(),
        };

        assert_eq!(user_msg.role, Role::User);
        assert_eq!(assistant_msg.role, Role::Assistant);
        assert_eq!(system_msg.role, Role::System);
    }

    #[test]
    fn test_multi_message_request() {
        let mut request = create_test_request();

        request.messages.push(ChatMessage {
            role: Role::Assistant,
            content: "Response".to_string(),
        });

        request.messages.push(ChatMessage {
            role: Role::User,
            content: "Follow-up".to_string(),
        });

        assert_eq!(request.messages.len(), 3);
        assert_eq!(request.messages[0].role, Role::User);
        assert_eq!(request.messages[1].role, Role::Assistant);
        assert_eq!(request.messages[2].role, Role::User);
    }
}

// Live integration tests (require API keys or running Thanos server)
#[cfg(test)]
#[cfg(feature = "integration_tests")]
mod live_provider_tests {
    use super::*;
    use thanos::providers::Provider;

    #[tokio::test]
    async fn test_ollama_local() {
        // Test connection to local Ollama if available
        let provider = thanos::providers::ollama::OllamaProvider::new(
            "http://localhost:11434".to_string(),
            "llama3.2".to_string(),
        );

        let request = create_test_request();
        let result = provider.chat_completion(&request).await;

        // If Ollama is running, this should succeed
        // If not, it will fail with connection error
        match result {
            Ok(response) => {
                println!("✓ Ollama connection successful");
                assert!(!response.choices.is_empty());
            }
            Err(e) => {
                println!("✗ Ollama not available: {}", e);
            }
        }
    }
}
