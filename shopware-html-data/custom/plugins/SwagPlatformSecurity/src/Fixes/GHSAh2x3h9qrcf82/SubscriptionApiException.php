<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAh2x3h9qrcf82;

use Shopware\Core\Framework\HttpException;
use Shopware\Core\Framework\Log\Package;
use Symfony\Component\HttpFoundation\Response;

#[Package('checkout')]
class SubscriptionApiException extends HttpException
{
    public const SUBSCRIPTION_NOT_FOUND_CODE = 'CHECKOUT__SUBSCRIPTION_NOT_FOUND';

    public static function subscriptionNotFound(string $subscriptionId): self
    {
        return new self(
            Response::HTTP_NOT_FOUND,
            self::SUBSCRIPTION_NOT_FOUND_CODE,
            'Subscription with id {{ id }} not found.',
            ['id' => $subscriptionId]
        );
    }
}
