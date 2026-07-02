<?php declare(strict_types=1);

namespace Swag\Security\Components;

use Shopware\Core\Framework\Log\Package;

#[Package('framework')]
class State
{
    final public const CONFIG_PREFIX = 'SwagPlatformSecurity.config.';

    /**
     * @param list<class-string<AbstractSecurityFix>> $availableFixes
     * @param list<class-string<AbstractSecurityFix>> $activeFixes
     */
    public function __construct(
        private readonly array $availableFixes,
        private readonly array $activeFixes
    ) {
    }

    /**
     * @return list<class-string<AbstractSecurityFix>>
     */
    public function getActiveFixes(): array
    {
        return $this->activeFixes;
    }

    /**
     * @return list<class-string<AbstractSecurityFix>>
     */
    public function getAvailableFixes(): array
    {
        return $this->availableFixes;
    }

    public function isActive(string $ticket): bool
    {
        foreach ($this->getActiveFixes() as $validFix) {
            if ($validFix::getTicket() === $ticket) {
                return true;
            }
        }

        return false;
    }
}
