use serde::{Deserialize, Serialize};

/// Chat message role
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    System,
    User,
    Assistant,
}

/// A single message in a conversation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: Role,
    pub content: String,
}

/// Chat completion request
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatRequest {
    pub model: String,
    pub messages: Vec<ChatMessage>,
    #[serde(default)]
    pub stream: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub temperature: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub max_tokens: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub top_p: Option<f32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub system: Option<String>,
}

/// Chat completion response (streaming or complete)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatResponse {
    pub provider: String,
    pub model: String,
    pub content: String,
    #[serde(default)]
    pub done: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub usage: Option<Usage>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub finish_reason: Option<String>,
}

/// Token usage statistics
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Usage {
    pub prompt_tokens: i32,
    pub completion_tokens: i32,
    pub total_tokens: i32,
}

/// Provider type (matches config)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Provider {
    Anthropic,
    AnthropicMax,
    OpenAI,
    Xai,
    Gemini,
    GithubCopilot,
    Ollama,
    Omen,
}

impl Provider {
    pub fn as_str(&self) -> &'static str {
        match self {
            Provider::Anthropic => "anthropic",
            Provider::AnthropicMax => "anthropic_max",
            Provider::OpenAI => "openai",
            Provider::Xai => "xai",
            Provider::Gemini => "gemini",
            Provider::GithubCopilot => "github_copilot",
            Provider::Ollama => "ollama",
            Provider::Omen => "omen",
        }
    }

    pub fn from_str(s: &str) -> Option<Self> {
        match s.to_lowercase().as_str() {
            "anthropic" => Some(Provider::Anthropic),
            "anthropic_max" => Some(Provider::AnthropicMax),
            "openai" => Some(Provider::OpenAI),
            "xai" => Some(Provider::Xai),
            "gemini" => Some(Provider::Gemini),
            "github_copilot" => Some(Provider::GithubCopilot),
            "ollama" => Some(Provider::Ollama),
            "omen" => Some(Provider::Omen),
            _ => None,
        }
    }
}

/// Authentication method
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AuthMethod {
    ApiKey,
    #[serde(rename = "oauth")]
    OAuth,
    None,
}

/// Model information
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelInfo {
    pub id: String,
    pub provider: String,
    pub name: String,
    pub context_length: i32,
    pub max_output: i32,
    pub supports_streaming: bool,
    pub supports_functions: bool,
    pub supports_vision: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_provider_from_str() {
        assert_eq!(Provider::from_str("anthropic"), Some(Provider::Anthropic));
        assert_eq!(Provider::from_str("Anthropic"), Some(Provider::Anthropic));
        assert_eq!(Provider::from_str("ANTHROPIC"), Some(Provider::Anthropic));
        assert_eq!(Provider::from_str("anthropic_max"), Some(Provider::AnthropicMax));
        assert_eq!(Provider::from_str("openai"), Some(Provider::OpenAI));
        assert_eq!(Provider::from_str("xai"), Some(Provider::Xai));
        assert_eq!(Provider::from_str("gemini"), Some(Provider::Gemini));
        assert_eq!(Provider::from_str("github_copilot"), Some(Provider::GithubCopilot));
        assert_eq!(Provider::from_str("ollama"), Some(Provider::Ollama));
        assert_eq!(Provider::from_str("omen"), Some(Provider::Omen));
        assert_eq!(Provider::from_str("unknown"), None);
    }

    #[test]
    fn test_provider_as_str() {
        assert_eq!(Provider::Anthropic.as_str(), "anthropic");
        assert_eq!(Provider::AnthropicMax.as_str(), "anthropic_max");
        assert_eq!(Provider::OpenAI.as_str(), "openai");
        assert_eq!(Provider::Xai.as_str(), "xai");
        assert_eq!(Provider::Gemini.as_str(), "gemini");
        assert_eq!(Provider::GithubCopilot.as_str(), "github_copilot");
        assert_eq!(Provider::Ollama.as_str(), "ollama");
        assert_eq!(Provider::Omen.as_str(), "omen");
    }

    #[test]
    fn test_role_serialization() {
        assert_eq!(serde_json::to_string(&Role::User).unwrap(), r#""user""#);
        assert_eq!(serde_json::to_string(&Role::Assistant).unwrap(), r#""assistant""#);
        assert_eq!(serde_json::to_string(&Role::System).unwrap(), r#""system""#);
    }

    #[test]
    fn test_chat_message_creation() {
        let message = ChatMessage {
            role: Role::User,
            content: "Hello".to_string(),
        };

        assert_eq!(message.role, Role::User);
        assert_eq!(message.content, "Hello");
    }

    #[test]
    fn test_chat_request_defaults() {
        let request = ChatRequest {
            model: "test-model".to_string(),
            messages: vec![],
            stream: false,
            temperature: None,
            max_tokens: None,
            top_p: None,
            system: None,
        };

        assert!(!request.stream);
        assert!(request.temperature.is_none());
        assert!(request.max_tokens.is_none());
    }

    #[test]
    fn test_usage_calculation() {
        let usage = Usage {
            prompt_tokens: 100,
            completion_tokens: 50,
            total_tokens: 150,
        };

        assert_eq!(usage.total_tokens, usage.prompt_tokens + usage.completion_tokens);
    }

    #[test]
    fn test_auth_method_variants() {
        let api_key = AuthMethod::ApiKey;
        let oauth = AuthMethod::OAuth;
        let none = AuthMethod::None;

        assert_eq!(api_key, AuthMethod::ApiKey);
        assert_eq!(oauth, AuthMethod::OAuth);
        assert_eq!(none, AuthMethod::None);
        assert_ne!(api_key, oauth);
    }
}
