<?php declare(strict_types=1); /** @phpstan-ignore symplify.multipleClassLikeInFile */

namespace Swag\Security\Fixes\GHSAc4p7rwrgpf6p;

use Shopware\Core\Framework\Log\Package;
use Shopware\Core\Framework\MessageQueue\AsyncMessageInterface;
use Shopware\Core\Framework\MessageQueue\DeduplicatableMessageInterface;

if (class_exists(DeduplicatableMessageInterface::class)) {
    /**
     * @codeCoverageIgnore
     *
     * @internal only for use by the app-system
     */
    #[Package('framework')]
    class RotateAppSecretMessage implements AsyncMessageInterface, DeduplicatableMessageInterface
    {
        public function __construct(
            private readonly string $appId,
            private readonly string $trigger
        ) {
        }

        public function getAppId(): string
        {
            return $this->appId;
        }

        public function getTrigger(): string
        {
            return $this->trigger;
        }

        public function deduplicationId(): ?string
        {
            return $this->appId;
        }
    }
} else {
    /**
     * @codeCoverageIgnore
     *
     * @internal only for use by the app-system
     */
    #[Package('framework')]
    class RotateAppSecretMessage implements AsyncMessageInterface
    {
        public function __construct(
            private readonly string $appId,
            private readonly string $trigger
        ) {
        }

        public function getAppId(): string
        {
            return $this->appId;
        }

        public function getTrigger(): string
        {
            return $this->trigger;
        }
    }
}
