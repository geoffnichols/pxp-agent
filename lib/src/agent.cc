#include <pxp-agent/agent.hpp>
#include <pxp-agent/pxp_schemas.hpp>

#define LEATHERMAN_LOGGING_NAMESPACE "puppetlabs.pxp_agent.agent"
#include <leatherman/logging/logging.hpp>

#include <vector>

namespace PXPAgent {

Agent::Agent(const Configuration::Agent& agent_configuration)
        try
            : connector_ptr_ { new PXPConnector(agent_configuration) },
              request_processor_ { connector_ptr_, agent_configuration } {
} catch (PCPClient::connection_config_error& e) {
    throw Agent::Error { std::string { "failed to configure: " } + e.what() };
}

void Agent::start() {
    // TODO(ale): add associate response callback

    connector_ptr_->registerMessageCallback(
        PXPSchemas::BlockingRequestSchema(),
        [this](const PCPClient::ParsedChunks& parsed_chunks) {
            blockingRequestCallback(parsed_chunks);
        });

    connector_ptr_->registerMessageCallback(
        PXPSchemas::NonBlockingRequestSchema(),
        [this](const PCPClient::ParsedChunks& parsed_chunks) {
            nonBlockingRequestCallback(parsed_chunks);
        });

    try {
        connector_ptr_->connect();
    } catch (PCPClient::connection_config_error& e) {
        LOG_ERROR("Failed to configure the underlying communications layer: %1%",
                  e.what());
        throw Agent::Error { "failed to configure the underlying communications"
                             "layer" };
    } catch (PCPClient::connection_fatal_error& e) {
        LOG_ERROR("Failed to connect: %1%", e.what());
        throw Agent::Error { "failed to connect" };
    }

    // The agent is now connected and the request handlers are set;
    // we can now call the monitoring method that will block this
    // thread of execution.
    // Note that, in case the underlying connection drops, the
    // connector will keep trying to re-establish it indefinitely
    // (the max_connect_attempts is 0 by default).
    try {
        connector_ptr_->monitorConnection();
    } catch (PCPClient::connection_fatal_error) {
        throw Agent::Error { "failed to reconnect" };
    }
}

void Agent::blockingRequestCallback(
                const PCPClient::ParsedChunks& parsed_chunks) {
    request_processor_.processRequest(RequestType::Blocking, parsed_chunks);
}

void Agent::nonBlockingRequestCallback(
                const PCPClient::ParsedChunks& parsed_chunks) {
    request_processor_.processRequest(RequestType::NonBlocking, parsed_chunks);
}

}  // namespace PXPAgent
