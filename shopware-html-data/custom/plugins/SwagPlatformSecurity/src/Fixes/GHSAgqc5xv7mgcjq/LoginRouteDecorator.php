<?php declare(strict_types=1);

namespace Swag\Security\Fixes\GHSAgqc5xv7mgcjq;

use Shopware\Core\Checkout\Customer\CustomerException;
use Shopware\Core\Checkout\Customer\Exception\CustomerNotFoundException;
use Shopware\Core\Checkout\Customer\SalesChannel\AbstractLoginRoute;
use Shopware\Core\Framework\Validation\DataBag\RequestDataBag;
use Shopware\Core\System\SalesChannel\ContextTokenResponse;
use Shopware\Core\System\SalesChannel\SalesChannelContext;

/**
 * GHSA-gqc5-xv7m-gcjq: Store API login account enumeration.
 * Normalizes CustomerNotFoundException to BadCredentialsException so that
 * "email not found" and "wrong password" return the same error to the client.
 */
class LoginRouteDecorator extends AbstractLoginRoute
{
    public function __construct(
        private readonly AbstractLoginRoute $inner
    ) {
    }

    public function getDecorated(): AbstractLoginRoute
    {
        return $this->inner;
    }

    public function login(RequestDataBag $data, SalesChannelContext $context): ContextTokenResponse
    {
        try {
            return $this->inner->login($data, $context);
        } catch (CustomerNotFoundException) {
            throw CustomerException::badCredentials();
        }
    }
}
