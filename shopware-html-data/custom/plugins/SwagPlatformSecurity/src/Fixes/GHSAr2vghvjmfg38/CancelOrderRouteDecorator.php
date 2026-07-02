<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAr2vghvjmfg38;

use Shopware\Core\Checkout\Order\SalesChannel\AbstractCancelOrderRoute;
use Shopware\Core\Checkout\Order\SalesChannel\CancelOrderRouteResponse;
use Shopware\Core\System\SalesChannel\SalesChannelContext;
use Shopware\Core\System\SystemConfig\SystemConfigService;
use Symfony\Component\HttpFoundation\Request;

class CancelOrderRouteDecorator extends AbstractCancelOrderRoute
{
    public function __construct(
        private readonly AbstractCancelOrderRoute $inner,
        private readonly SystemConfigService $systemConfigService,
    ) {
    }

    public function getDecorated(): AbstractCancelOrderRoute
    {
        return $this->inner;
    }

    public function cancel(Request $request, SalesChannelContext $context): CancelOrderRouteResponse
    {
        if (!$this->systemConfigService->getBool('core.cart.enableOrderRefunds', $context->getSalesChannelId())) {
            throw new OrderNotCancellableException();
        }

        return $this->inner->cancel($request, $context);
    }
}
